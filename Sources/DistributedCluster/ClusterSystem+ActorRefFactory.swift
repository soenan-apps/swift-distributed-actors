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

extension ClusterSystem: ActorRefFactory {
    @discardableResult
    public func spawn<Message>(
        _ naming: ActorNaming,
        _ behavior: Behavior<Message>,
        props: Props = Props(),
        file: String = #filePath,
        line: UInt = #line
    ) throws -> ActorRef<Message> where Message: Codable {
        try self.serialization.ensureSerializer(Message.self, file: file, line: line)
        return try self.spawn(using: self.userProvider, behavior, name: naming, props: props)
    }

    /// INTERNAL API
    ///
    /// Implementation note:
    /// `wellKnown` here means that the actor always exists and must be addressable without receiving a
    /// reference / path to it. This is for example necessary
    /// to discover the receptionist actors on all nodes in order to replicate state between them. The
    /// incarnation of those actors will be `ActorIncarnation.wellKnown`.
    /// This also means that there will only be one instance of that actor that will stay alive for the whole
    /// lifetime of the system.
    /// Appropriate supervision strategies should be configured for these types of actors.
    public func spawnSystemActor<Message>(
        _ naming: ActorNaming,
        _ behavior: Behavior<Message>,
        props: Props = Props()
    ) throws -> ActorRef<Message>
    where Message: Codable {
        try self.serialization.ensureSerializer(Message.self)
        return try self.spawn(using: self.systemProvider, behavior, name: naming, props: props)
    }

    /// Initializes a system actor and enqueues the `.start` message in the mailbox, but does not schedule
    /// the actor. The actor must be manually scheduled later by calling `wakeUp` on the returned `LazyStart`.
    ///
    /// Delaying the start of an actor is necessary when creating actors from within `ClusterSystem.init`
    /// to prevent them from running before the system has been fully initialized, which could lead to accessing
    /// uninitialized fields and cause system crashes.
    ///
    /// Otherwise this function behaves the same as `spawnSystemActor`.
    ///
    /// **CAUTION** This methods MUST NOT be used from outside of `ClusterSystem.init`.
    internal func prepareSystemActor<Message>(
        _ naming: ActorNaming,
        _ behavior: Behavior<Message>,
        props: Props = Props()
    ) throws -> LazyStart<Message>
    where Message: Codable {
        let ref: ActorRef<Message> = try self.spawn(
            using: self.systemProvider,
            behavior,
            name: naming,
            props: props,
            startImmediately: false
        )
        return LazyStart(ref: ref)
    }

    // Actual spawn implementation, minus the leading "$" check on names;
    internal func spawn<Message>(
        using provider: ActorRefProvider,
        _ behavior: Behavior<Message>,
        name naming: ActorNaming,
        props: Props = Props(),
        startImmediately: Bool = true
    ) throws -> ActorRef<Message>
    where Message: Codable {
        try behavior.validateAsInitial()

        let incarnation: ActorIncarnation = props.wellKnown ? .wellKnown : .random()
        let id: ActorID = try self.withNamingContext { context in
            let actorName: String = naming.makeName(&context)

            return try provider.rootAddress.makeChildID(name: actorName, incarnation: incarnation)
        }

        let actorDispatcher: MessageDispatcher = self.messageDispatcher(for: props)
        return try provider.spawn(
            system: self,
            configuration: (behavior: behavior, props: props),
            id: id,
            dispatcher: actorDispatcher,
            startImmediately: startImmediately
        )
    }

    // Actual spawn implementation, minus the leading "$" check on names;
    internal func spawn<Message>(
        using provider: ActorRefProvider,
        _ behavior: Behavior<Message>,
        id: ActorID,
        props: Props,
        startImmediately: Bool = true
    ) throws -> ActorRef<Message>
    where Message: Codable {
        try behavior.validateAsInitial()

        let actorDispatcher: MessageDispatcher = self.messageDispatcher(for: props)
        return try provider.spawn(
            system: self,
            configuration: (behavior: behavior, props: props),
            id: id,
            dispatcher: actorDispatcher,
            startImmediately: startImmediately
        )
    }

    // Reserve an actor address.
    internal func reserveName<Act>(
        type _: Act.Type,
        props: Props
    ) throws -> ActorID where Act: DistributedActor {
        let incarnation: ActorIncarnation = props.wellKnown ? .wellKnown : .random()
        let provider: ActorRefProvider = props.systemActor ? self.systemProvider : self.userProvider

        return try self.withNamingContext { context in
            let name: String
            if let knownName = props.knownActorName {
                name = knownName
            } else {
                var baseName: String = "\(Act.self)"
                if let genericsAngleBracket = baseName.firstIndex(of: "<") {
                    baseName = "\(baseName[..<genericsAngleBracket])"
                }
                let naming: ActorNaming = ActorNaming.prefixed(with: baseName)
                name = naming.makeName(&context)
            }

            let id: ActorID = try provider.rootAddress.makeChildID(name: name, incarnation: incarnation)
            guard self.reservedNames.insert(id).inserted else {
                fatalError(
                    """
                    Attempted to reserve duplicate actor address: \(id.detailedDescription),
                    reserved: \(self.reservedNames.map(\.detailedDescription))
                    """
                )
            }

            return id
        }
    }

    public func spawnDistributedActor<Message>(
        _ behavior: Behavior<Message>,
        identifiedBy id: ClusterSystem.ActorID
    ) -> ActorRef<Message> where Message: Codable {
        var props: Props = id.metadata.actorProps?.props ?? Props()
        props.distributedActor = true

        let provider: ActorRefProvider
        if props.systemActor {
            provider = self.systemProvider
        } else {
            provider = self.userProvider
        }

        do {
            return try self.spawn(using: provider, behavior, id: id, props: props)
            // try!-safe, since the naming must have been correct
        } catch {
            fatalError(
                """
                Failed to spawn DistributedActor, id: \(id.fullDescription); \
                props: \(id.metadata.actorProps?.props ?? Props()), error: \(error)
                """
            )
        }
    }

    private func messageDispatcher(for props: Props) -> MessageDispatcher {
        switch props.dispatcher {
        case .default:
            return self.dispatcher

        case .callingThread:
            return CallingThreadDispatcher()

        case .dispatchQueue(let queue):
            return DispatchQueueDispatcher(queue: queue)

        case .nio(let group):
            return NIOEventLoopGroupDispatcher(group)

        default:
            fatalError("selected dispatcher [\(props.dispatcher)] not implemented yet; ")
        }
    }
}
