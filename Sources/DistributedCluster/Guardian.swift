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

import CDistributedActorsMailbox
import Dispatch
import Logging
import Metrics

import struct NIO.ByteBuffer

/// INTERNAL API: May change without any prior notice.
///
/// Represents the an "top level" actor which is the parent of all actors spawned on by the system itself
/// (unlike actors spawned from within other actors, by using `context.spawn`).
public class Guardian: ActorTreeTraversable, CustomStringConvertible {
    @usableFromInline internal let actorID: ActorID
    internal var id: ActorID {
        self.actorID
    }

    internal var path: ActorPath {
        self.id.path
    }

    internal let name: String

    // any access to children has to be protected by `lock`
    private var childrenStorage: Children
    private let childrenLock: ClusterMutex = .init()
    private var children: Children {
        self.childrenLock.synchronized { () in
            childrenStorage
        }
    }

    private let allChildrenRemoved: ClusterCondition = .init()
    private var stopping: Bool = false
    internal weak var system: ClusterSystem?

    internal var ref: ActorRef<Never> {
        .init(.guardian(self))
    }
    internal var deadLetters: ActorRef<DeadLetter> {
        ActorRef(.deadLetters(.init(Logger(label: "Guardian(\(self.id))"), id: self.id, system: self.system)))
    }
    public var description: String {
        "Guardian(\(self.id.path))"
    }

    internal init(parent: ReceivesSystemMessages, name: String, localNode: Cluster.Node, system: ClusterSystem) {
        assert(parent.id == ActorID.localRoot(on: localNode), "A Guardian MUST live directly under the `/` path.")

        do {
            self.actorID = try ActorPath(root: name).makeLocalID(on: localNode, incarnation: .wellKnown)
        } catch {
            fatalError(
                """
                Illegal Guardian path, as those are only to be created by ClusterSystem startup, \
                considering this fatal.
                """
            )
        }
        self.childrenStorage = Children()
        self.system = system
        self.name = name
    }
    @usableFromInline
    internal func trySendUserMessage(_ message: Any, file: String = #filePath, line: UInt = #line) {
        self.deadLetters.tell(DeadLetter(message, recipient: self.id), file: file, line: line)
    }

    private func removeTerminatedChild(_ ref: AddressableActorRef) {
        self.childrenLock.synchronized {
            _ = self.childrenStorage.removeChild(identifiedBy: ref.id)
            // if we are stopping and all children have been stopped,
            // we need to notify waiting threads about it
            if self.stopping, self.childrenStorage.isEmpty {
                self.allChildrenRemoved.signalAll()
            }
        }
    }

    internal func sendSystemMessage(_ message: SystemMessages, file: String = #filePath, line: UInt = #line) {
        switch message {
        case let .childTerminated(ref, circumstances):
            self.removeTerminatedChild(ref)

            switch circumstances {
            case .escalating(let failure):
                guard let system = self.system else {
                    print(
                        """
                        [error] Failure escalated to \(self) yet system already not available. Already \
                        shutting down? Failure: \(failure)
                        """
                    )
                    return
                }

                // Shut down actor system
                let shutdownMessage: String = """
                    Escalated failure from [\(ref.id)] reached top-level guardian \
                    [\(self.id.path)], SHUTTING DOWN ClusterSystem! \
                    (This can be configured in `system.settings.failure.onGuardianFailure`). \
                    Failure was: \(failure)
                    """
                system.log.error(
                    "\(shutdownMessage)",
                    metadata: [
                        "actor/path": "\(self.id.path)",
                        "error": "\(failure)",
                    ]
                )

                _ = Task {
                    do {
                        try await system.shutdown().wait()
                    } catch {
                        fatalError("Guardian shutdown failed: \(error)")
                    }
                    print("Guardian shutdown of [\(system.name)] ClusterSystem complete.")
                }

            case .failed:
                ()  // ignore, we only react to escalations

            case .stopped:
                ()  // ignore, we only react to escalations
            }

        default:
            CDistributedActorsMailbox.sact_dump_backtrace()
            fatalError(
                "The \(self.id) actor MUST NOT receive any messages. Yet received \(message); Sent at \(file):\(line)"
            )
        }
    }

    @usableFromInline
    internal func asHashable() -> AnyHashable {
        AnyHashable(self.id)
    }

    internal func makeChild<Message>(
        path: ActorPath,
        spawn: () throws -> ActorShell<Message>
    ) throws -> ActorRef<Message> {
        try self.childrenLock.synchronized {
            if self.stopping {
                throw ActorContextError(
                    .alreadyStopping("system: \(self.system?.name ?? "<nil>")"),
                    file: #fileID,
                    line: #line
                )
            }

            if let existing = self.childrenStorage.findID(named: path.name) {
                throw ClusterSystemError(
                    .duplicateActorPath(path: path, existing: existing)
                )
            }

            let cell: ActorShell<Message> = try spawn()
            self.childrenStorage.insert(cell)

            return cell.myself
        }
    }

    internal func stopChild(_ childRef: AddressableActorRef) throws {
        try self.childrenLock.synchronized {
            guard self.childrenStorage.contains(identifiedBy: childRef.id) else {
                throw ActorContextError(
                    .attemptedStoppingNonChildActor(ref: childRef),
                    file: #fileID,
                    line: #line
                )
            }

            if self.childrenStorage.removeChild(identifiedBy: childRef.id) {
                childRef.sendSystemMessage(.stop)
            }
        }
    }

    /// Stops all children and waits for them to signal termination
    internal func stopAllAwait() {
        self.childrenLock.synchronized {
            if self.childrenStorage.isEmpty {
                // if there are no children, we are done
                self.stopping = true
                return
            }
            if self.stopping {
                // stopping has already been initiated, so we only have to wait
                // for all children to be removed
                self.allChildrenRemoved.wait(childrenLock)  // reason for not using our ReadWriteLock
                return
            }

            // set stopping, so no new actors can be created
            self.stopping = true

            // tell all children to stop and wait for them to be stopped
            self.childrenStorage.stopAll()
            // extra check because adapted refs get removed immediately
            if !self.childrenStorage.isEmpty {
                self.allChildrenRemoved.wait(childrenLock)
            }
        }
    }
    internal func traverse<T>(
        context: TraversalContext<T>,
        _ visit: (TraversalContext<T>, AddressableActorRef) -> TraversalDirective<T>
    ) -> TraversalResult<T> {
        let childSnapshot: Children = self.children

        var traversalContext: TraversalContext<T> = context.deeper
        let directive: TraversalDirective<T> = visit(context, self.ref.asAddressable)
        switch directive {
        case .continue:
            return childSnapshot.traverse(context: traversalContext, visit)

        case .accumulateSingle(let value):
            traversalContext.accumulated.append(value)
            return childSnapshot.traverse(context: traversalContext, visit)

        case .accumulateMany(let values):
            traversalContext.accumulated.append(contentsOf: values)
            return childSnapshot.traverse(context: traversalContext, visit)

        case .abort(let err):
            return .failed(err)
        }
    }

    internal func resolve<Message>(context: ResolveContext<Message>) -> ActorRef<Message> {
        guard let selector = context.selectorSegments.first else {
            fatalError("Expected selector in guardian.resolve()!")
        }

        if self.id.name == selector.value {
            return self.children.resolve(context: context.deeper)
        }
        return context.personalDeadLetters
    }

    internal func resolveUntyped(context: ResolveContext<Never>) -> AddressableActorRef {
        guard let selector = context.selectorSegments.first else {
            fatalError("Expected selector in guardian.resolve()!")
        }

        if self.name == selector.value {
            return self.children.resolveUntyped(context: context.deeper)
        }
        return context.personalDeadLetters.asAddressable
    }
}
