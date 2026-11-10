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

import Dispatch
import Logging
import NIO

extension ActorShell {
    internal func spawn<M>(_ naming: ActorNaming, props: Props, _ behavior: Behavior<M>) throws -> ActorRef<M> {
        let name: String = naming.makeName(&self.namingContext)

        try behavior.validateAsInitial()
        try self.validateUniqueName(name)  // reserve name

        let incarnation: ActorIncarnation = props.wellKnown ? .wellKnown : .random()
        let id: ActorID = try self.id.makeChildID(name: name, incarnation: incarnation)

        let dispatcher: MessageDispatcher
        switch props.dispatcher {
        case .default:
            dispatcher = self.messageDispatcher  // this is dispatcher inheritance, not sure about it

        case .callingThread:
            dispatcher = CallingThreadDispatcher()

        case let .nio(group):
            dispatcher = NIOEventLoopGroupDispatcher(group)

        default:
            fatalError("not implemented yet, only default dispatcher and calling thread one work")
        }

        let actor: ActorShell<M> = ActorShell<M>(
            system: self.system,
            parent: self.myself.asAddressable,
            behavior: behavior,
            id: id,
            props: props,
            dispatcher: dispatcher
        )
        let mailbox: Mailbox<M> = Mailbox(shell: actor)

        if self.system.settings.logging.verboseSpawning {
            log.trace("Spawning [\(behavior)], on path: [\(id.path)]")
        }

        let cell: ActorCell<M> = ActorCell(
            id: id,
            actor: actor,
            mailbox: mailbox
        )

        self.children.insert(actor)

        actor.set(ref: cell)
        cell.sendSystemMessage(.start, file: #filePath, line: #line)

        return .init(.cell(cell))
    }

    internal func stopChild<T>(child ref: ActorRef<T>) throws {
        guard ref.id.path.isChildPathOf(self.id.path) else {
            if ref.id == self.myself.id {
                throw ActorContextError(.attemptedStoppingMyselfUsingContext(ref: ref.asAddressable))
            }
            throw ActorContextError(.attemptedStoppingNonChildActor(ref: ref.asAddressable))
        }

        if self.children.markAsStoppingChild(identifiedBy: ref.id) {
            ref.sendSystemMessage(.stop, file: #filePath, line: #line)
        }
    }

    internal func stopAllChildren() {
        self.children.stopAll()
    }

    private func validateUniqueName(_ name: String) throws {
        if let existing = children.findID(named: name) {
            let childPath: ActorPath = try self.id.path.makeChildPath(name: name)
            throw ActorContextError(.duplicateActorPath(path: childPath, existing: existing))
        }
    }
}
