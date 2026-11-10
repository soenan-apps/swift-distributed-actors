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

import Atomics
import CDistributedActorsMailbox
import Logging
import Metrics
import NIO

/// INTERNAL API
///
/// The shell is responsible for interpreting messages using the current behavior.
/// In simplified terms, it can be thought of as "the actual actor," as it is the most central piece where
/// all actor interactions with messages, user code, and the mailbox itself happen.
///
/// The shell is mutable, and full of dangerous and carefully threaded/ordered code, be extra cautious.
public final class ActorShell<Message: Codable>: ActorContext<Message>, AbstractShellProtocol {
    // The phrase that "actor change their behavior" can be understood quite literally;
    // On each message interpretation the actor may return a new behavior that will be handling the next message.
    @usableFromInline internal var behavior: Behavior<Message>

    @usableFromInline internal let parentRef: AddressableActorRef

    @usableFromInline internal let actorID: ActorID

    internal let actorProps: Props

    internal var namingContext: ActorNamingContext

    @usableFromInline internal let metrics: ActiveActorMetrics

    @usableFromInline internal let messageDispatcher: MessageDispatcher

    @usableFromInline internal var actorSystem: ClusterSystem?

    internal var subReceives: [AnySubReceiveId: ((SubMessageCarry) throws -> Behavior<Message>, AbstractAdapter)] = [:]
    private var messageAdapter: ActorRefAdapter<Message>?
    internal var messageAdapters: [MessageAdapterClosure] = []
    override public var system: ClusterSystem {
        if let currentSystem = self.actorSystem {
            return currentSystem
        }
        return fatalErrorBacktrace(
            """
            Accessed context.system (of actor: \(self.id)) while system was already stopped and released, \
            this should never happen. \
            This may indicate that the context was stored somewhere or passed to another asynchronously \
            executing non-actor context, \
            which is always a programming bug (!). An actor's context MUST NOT ever be accessed by anyone \
            else rather than the actor itself.
            """
        )
    }

    /// Guaranteed to be set during ActorRef creation
    /// Must never be exposed to users, rather expose the `ActorRef<Message>` by calling `myself`.
    @usableFromInline internal lazy var actorCell: ActorCell<Message> = .init(
        id: self.id,
        actor: self,
        mailbox: Mailbox(shell: self, maxRunLength: 100)
    )

    override public var timers: BehaviorTimers<Message> {
        self.behaviorTimers
    }

    internal lazy var behaviorTimers: BehaviorTimers<Message> = BehaviorTimers(context: self)

    // We always have a supervisor in place, even if it is just the ".stop" one.
    internal let supervisor: Supervisor<Message>
    // we can likely optimize not having to call "through" supervisor if we are .stop anyway

    // Implementation of DeathWatch
    @usableFromInline internal var deathWatchState: DeathWatchImpl<Message>?

    private let childrenLock: ReadWriteLock = ReadWriteLock()
    // All access must be protected with `childrenLock`, or via `children` helper
    internal var childActors: Children = .init()
    override public var children: Children {
        get {
            self.childrenLock.lockRead()
            defer { self.childrenLock.unlock() }
            return self.childActors
        }
        set {
            self.childrenLock.lockWrite()
            defer { self.childrenLock.unlock() }
            self.childActors = newValue
        }
    }

    /// Returns this actors "self" actor reference, which can be freely shared across
    /// threads, actors, and even nodes (if clustering is used).
    ///
    /// Warning: Do not use after actor has terminated (!)
    override public var myself: ActorRef<Message> {
        .init(.cell(self.actorCell))
    }

    override public var props: Props {
        self.actorProps
    }

    override public var id: ActorID {
        self.actorID
    }

    // Implementation note: Watch out when accessing from outside of an actor run, myself could have been unset (!)
    override public var path: ActorPath {
        self.actorID.path
    }

    // Implementation note: Watch out when accessing from outside of an actor run, myself could have been unset (!)
    override public var name: String {
        self.actorID.name
    }

    // access only from within actor
    private var actorLogger: Logger
    override public var log: Logger {
        get {
            self.actorLogger
        }
        set {
            self.actorLogger = newValue
        }
    }

    internal init(
        system: ClusterSystem,
        parent: AddressableActorRef,
        behavior: Behavior<Message>,
        id: ActorID,
        props: Props,
        dispatcher: MessageDispatcher
    ) {
        self.actorSystem = system
        self.parentRef = parent
        self.messageDispatcher = dispatcher

        self.behavior = behavior
        self.actorID = id
        self.actorProps = props
        self.actorLogger = Logger.make(system.log, path: id.path)

        self.supervisor = Supervision.supervisorFor(system, initialBehavior: behavior, props: props.supervision)
        self.deathWatchState = DeathWatchImpl(
            nodeDeathWatcher: system.nodeDeathWatcherStore.load()?.value ?? system.deadLetters.adapted()
        )

        self.namingContext = ActorNamingContext()

        self.metrics = ActiveActorMetrics(system: system, id: id, props: props.metrics)

        // replace with TestMetrics which we could use to inspect the start/stop counts
        #if SACT_TESTS_LEAKS
        // We deliberately only count user actors here, because the number of
        // system actors may change over time and they are also not relevant for
        // this type of test.
        if id.segments.first?.value == "user" {
            system.userCellInitCounter.loadThenWrappingIncrement(ordering: .relaxed)
        }
        #endif

        super.init()

        system.metrics.recordActorStart(self)
    }

    /// Spawns a child after ensuring its message serializer is available.
    @discardableResult
    override public func spawn<M>(
        _ naming: ActorNaming,
        _ behavior: Behavior<M>,
        props: Props = Props(),
        file: String = #filePath,
        line: UInt = #line
    ) throws -> ActorRef<M>
    where M: Codable {
        try self.system.serialization.ensureSerializer(M.self, file: file, line: line)
        return try self.spawn(naming, props: props, behavior)
    }

    /// Spawns a child and watches it for termination.
    @discardableResult
    override public func spawnWatch<M>(
        _ naming: ActorNaming,
        _ behavior: Behavior<M>,
        props: Props = Props(),
        file _: String = #filePath,
        line _: UInt = #line
    ) throws -> ActorRef<M>
    where M: Codable {
        self.watch(try self.spawn(naming, props: props, behavior))
    }

    override public func stop<M: Codable>(child ref: ActorRef<M>) throws {
        try self.stopChild(child: ref)
    }

    @discardableResult
    override public func watch<Watchee>(
        _ watchee: Watchee,
        with terminationMessage: Message? = nil,
        file: String = #filePath,
        line: UInt = #line
    ) -> Watchee where Watchee: DeathWatchable {
        self.deathWatch.watch(watchee: watchee, with: terminationMessage, myself: self, file: file, line: line)
        return watchee
    }

    @discardableResult
    override public func unwatch<Watchee>(
        _ watchee: Watchee,
        file: String = #filePath,
        line: UInt = #line
    ) -> Watchee where Watchee: DeathWatchable {
        self.deathWatch.unwatch(watchee: watchee, myself: self.myself, file: file, line: line)
        return watchee
    }
    override internal func forceStop() {
        do {
            try self.becomeNext(behavior: .stop(reason: .stopMyself))
        } catch {
            self.log.warning("Illegal attempt to stop actor!")
        }
    }

    @usableFromInline
    override internal func subReceive(
        identifiedBy identifier: AnySubReceiveId
    ) -> ((SubMessageCarry) throws -> Behavior<Message>)? {
        self.subReceives[identifier]?.0
    }

    override public func subReceive<SubMessage>(
        _ id: SubReceiveId<SubMessage>,
        _ subType: SubMessage.Type,
        _ closure: @escaping (SubMessage) throws -> Void
    ) -> ActorRef<SubMessage>
    where SubMessage: Codable {
        self.registerSubReceive(id, subType, closure)
    }

    override public func messageAdapter<From>(
        from fromType: From.Type,
        adapt: @escaping (From) -> Message?
    ) -> ActorRef<From>
    where From: Codable {
        do {
            let metaType: MetaType<From> = MetaType(fromType)
            let anyAdapter: (Any) -> Message? = { message in
                guard let typedMessage = message as? From else {
                    fatalError(
                        """
                        messageAdapter was applied to message [\(message)] of incompatible type \
                        `\(String(reflecting: type(of: message)))` message.This should never happen, as at \
                        compile-time the message type should have been enforced to be `\(From.self)`.
                        """
                    )
                }

                return adapt(typedMessage)
            }

            self.messageAdapters.removeAll { adapter in
                adapter.metaType.is(metaType)
            }
            self.messageAdapters.insert(
                MessageAdapterClosure(metaType: metaType, closure: anyAdapter),
                at: self.messageAdapters.startIndex
            )

            if let adapter: ActorRefAdapter<Message> = self.messageAdapter {
                return .init(.adapter(adapter))
            }
            let adaptedAddress: ActorID = try self.id.makeChildID(
                name: ActorNaming.adapter.makeName(&self.namingContext),
                incarnation: .wellKnown
            )
            let adapter: ActorRefAdapter<Message> = ActorRefAdapter(
                fromType: fromType,
                to: self.myself,
                id: adaptedAddress
            )

            self.messageAdapter = adapter
            self.childActors.insert(adapter)  // separate adapters collection?

            return .init(.adapter(adapter))
        } catch {
            fatalError(
                """
                Failed while creating message adapter. This should never happen, since message adapters have \
                a unique name.
                Maybe `ActorContext.messageAdapter` was accessed concurrently (which is unsafe!)?
                Error: \(error)
                """
            )
        }
    }

    deinit {
        traceLog_Cell("deinit cell \(self.actorID)")
        #if SACT_TESTS_LEAKS
        if self.id.segments.first?.value == "user" {
            self.system.userCellInitCounter.loadThenWrappingDecrement(ordering: .relaxed)
        }
        #endif
        self.system.metrics.recordActorStop(self)

        self.actorSystem = nil
    }

}
