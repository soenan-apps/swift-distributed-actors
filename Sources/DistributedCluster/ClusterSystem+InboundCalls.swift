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

import Distributed
import DistributedActorsConcurrencyHelpers
import Logging
import NIO

extension ClusterSystem {
    internal func receiveInvocation(_ invocation: InvocationMessage, recipient: ActorID, on channel: Channel) {
        self.log.trace(
            "Receive invocation: \(invocation) to: \(recipient.detailedDescription)",
            metadata: [
                "recipient/id": "\(recipient.detailedDescription)",
                "invocation": "\(invocation)",
            ]
        )

        guard self.clusterShell != nil else {
            self.log.error(
                "Cluster has shut down already, yet received message. Message will be dropped: \(invocation)"
            )
            return
        }

        Task {
            var decoder: ClusterInvocationDecoder = ClusterInvocationDecoder(system: self, message: invocation)

            let target: RemoteCallTarget = invocation.target
            let resultHandler: ClusterInvocationResultHandler = ClusterInvocationResultHandler(
                system: self,
                callID: invocation.callID,
                channel: channel,
                recipient: recipient
            )

            do {
                guard let actor = self.resolveLocalAnyDistributedActor(id: recipient) else {
                    self.deadLetters.tell(DeadLetter(invocation, recipient: recipient))
                    throw DeadLetterError(recipient: recipient)
                }

                try await executeDistributedTarget(
                    on: actor,
                    target: target,
                    invocationDecoder: &decoder,
                    handler: resultHandler
                )
            } catch {
                do {
                    try await resultHandler.onThrow(error: error)
                } catch {
                    self.log.warning("Unable to invoke result handler for \(invocation.target) call, error: \(error)")
                }
            }
        }
    }

    internal func receiveRemoteCallReply(_ reply: any AnyRemoteCallReply) {
        self.inFlightCallLock.withLockVoid {
            guard let continuation = self.inFlightCalls.removeValue(forKey: reply.callID) else {
                // A timed-out call no longer has a continuation.
                self.log.warning(
                    "Missing continuation for remote call \(reply.callID). Reply will be dropped: \(reply)"
                )
                return
            }
            continuation.resume(returning: reply)
        }
    }

    private func resolveLocalAnyDistributedActor(id: ActorID) -> (any DistributedActor)? {
        if self.settings.logging.verboseResolve {
            self.log.trace("Resolve as any DistributedActor: \(id)")
        }

        // If it has an interceptor installed, we must pretend to resolve it as "remote",
        // though the actual messages will be delivered to the interceptor,
        // and not necessarily a remote destination.
        if let interceptor = id.context.remoteCallInterceptor {
            if self.settings.logging.verboseResolve {
                self.log.trace("Resolved \(id) as intercepted", metadata: ["interceptor": "\(interceptor)"])
            }
            return nil
        }

        // If the actor is not located on this node, immediately resolve as "remote"
        guard self.cluster.node == id.node else {
            self.log.trace("Resolve local failed, ID is for a remote host: \(id.node)", metadata: ["actor/id": "\(id)"])
            return nil
        }

        // Is it a well-known actor? If so, we need to special handle the resolution.
        if let wellKnownName = id.metadata.wellKnown {
            let wellKnownActor: (any DistributedActor)? = self.namingLock.withLock {
                self.managedWellKnownDistributedActors[wellKnownName]
            }

            return self.namingLock.withLock {
                if let wellKnownActor {
                    self.log.trace("Resolved \(id) well-known actor: \(wellKnownName)")
                    return wellKnownActor
                }
                self.log.trace(
                    "Resolve failed, no alive actor for well-known ID",
                    metadata: [
                        "actor/id": "\(id)",
                        "wellKnown/actors": "\(self.managedWellKnownDistributedActors.keys)",
                    ]
                )
                return nil
            }
        }

        // Resolve using the usual id lookup method
        let managed: (any DistributedActor)? = self.namingLock.withLock {
            self.managedDistributedActors.get(identifiedBy: id)
        }

        guard let managed else {
            self.logMissingLocalActor(id: id)
            return nil
        }

        return managed
    }

    private func logMissingLocalActor(id: ActorID) {
        self.namingLock.withLockVoid {
            self.log.trace(
                "Resolve failed, no alive actor for ID",
                metadata: [
                    "actor/id": "\(id.detailedDescription)",
                    "managed/ids": Logger.MetadataValue.array(
                        self.managedDistributedActors.underlying.values.compactMap { ref in
                            guard let actor = ref.actor else {
                                return nil
                            }
                            return Logger.MetadataValue.string("\(actor.id)")
                        }
                    ),
                ]
            )
        }
    }
}
