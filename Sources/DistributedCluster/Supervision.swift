// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Logging

/// Namespace for supervision associated types.
///
/// - SeeAlso: `SupervisionStrategy` for thorough documentation of supervision strategies and semantics.
@usableFromInline
internal enum Supervision {
    /// Represents (and unifies) actor failures, i.e. what happens when code running inside an actor throws,
    /// or if such code encounters a fault (such as `fatalError`, divides by zero or causes an out-of-bounds fault
    /// by un-safely accessing an array.
    @usableFromInline
    internal enum Failure: CustomStringConvertible, CustomDebugStringConvertible {
        /// The failure was caused by the actor throwing during its execution.
        /// The carried `Error` is the error that the actor has thrown.
        case error(Error)
        /// The failure was caused by the actor encountering a fault.
        /// The fault (i.e. error code) has been represented as an `Error` and carried inside this fault case.
        ///
        /// Do note that - by design - not all faults will be caught by supervision; some faults are
        /// considered so-called
        /// "fatal faults", and will not be offered to supervisors.
        case fault(Error)

        @usableFromInline internal var description: String {
            switch self {
            case .fault(let failure):
                switch failure {
                case let msgProcessingErr as MessageProcessingFailure:
                    return "fault(\(msgProcessingErr))"

                default:
                    return "fault(\(failure))"
                }

            case .error(let err):
                return "error(\(err))"
            }
        }

        @usableFromInline internal var debugDescription: String {
            switch self {
            case .fault(let failure):
                switch failure {
                case let msgProcessingErr as MessageProcessingFailure:
                    return "fault(\(String(reflecting: msgProcessingErr))"

                default:
                    return "fault(\(failure))"
                }

            case .error(let err):
                return "error(\(err))"
            }
        }

        internal func shouldBeHandled(bySupervisorHandling handledType: Error.Type) -> Bool {
            let supervisorHandlesEverything: Bool = handledType == Supervise.AllFailures.self

            func matchErrorTypes0() -> Bool {
                switch self {
                case .error(let error):
                    return handledType == Supervise.AllErrors.self || handledType == type(of: error)

                case .fault(let errorRepr):
                    return handledType == Supervise.AllFaults.self || handledType == type(of: errorRepr)
                }
            }

            return supervisorHandlesEverything || matchErrorTypes0()
        }
    }
    /// Thrown in the case of illegal supervision decisions being made, e.g. returning `.same` as decision,
    /// or other situations where supervision failed in some other way.
    internal enum SupervisionError: Error {
        case illegalDecision(String, handledError: Error, error: Error)
    }
    /// Internal conversion from supervision props to appropriate (potentially composite) `Supervisor<Message>`.
    internal static func supervisorFor<Message>(
        _: ClusterSystem,
        initialBehavior: Behavior<Message>,
        props: SupervisionProps
    ) -> Supervisor<Message> {
        func supervisorFor0(failureType: Error.Type, strategy: SupervisionStrategy) -> Supervisor<Message> {
            switch strategy {
            case let .restart(atMost, within, backoffStrategy):
                let restartLogic: RestartDecisionLogic = RestartDecisionLogic(
                    maxRestarts: atMost,
                    within: within,
                    backoffStrategy: backoffStrategy
                )
                return RestartingSupervisor(
                    initialBehavior: initialBehavior,
                    restartLogic: restartLogic,
                    failureType: failureType
                )

            case .escalate:
                return EscalatingSupervisor(failureType: failureType)

            case .stop:
                return StoppingSupervisor(failureType: failureType)
            }
        }

        switch props.supervisionMappings.count {
        case 0:
            // "no supervisor" is equivalent to a stopping one, this way we can centralize reporting
            // and logging of failures
            return StoppingSupervisor(failureType: Supervise.AllFailures.self)

        case 1:
            guard let typeBoundStrategy: ErrorTypeBoundSupervisionStrategy = props.supervisionMappings.first else {
                preconditionFailure("A single supervision mapping must contain its first element")
            }
            return supervisorFor0(failureType: typeBoundStrategy.failureType, strategy: typeBoundStrategy.strategy)

        default:
            var supervisors: [Supervisor<Message>] = []
            supervisors.reserveCapacity(props.supervisionMappings.count)
            for typeBoundStrategy in props.supervisionMappings {
                let supervisor: Supervisor<Message> = supervisorFor0(
                    failureType: typeBoundStrategy.failureType,
                    strategy: typeBoundStrategy.strategy
                )
                supervisors.append(supervisor)
            }
            return CompositeSupervisor(supervisors: supervisors)
        }
    }
}
