import AsyncAlgorithms
import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

internal enum SingletonStashTaskResult {
    case cluster
    case remoteCall
}

extension ClusterSingletonPluginClusteredTests {
    private static func greetingReply(
        singleton: TheSingleton,
        message: String,
        file: StaticString,
        line: UInt
    ) async throws -> String {
        do {
            let value: String = try await singleton.greet(name: message)
            pinfo(
                "    Passed '\(message)' -> [\(singleton)]: reply: \(value)",
                file: file,
                line: line
            )
            return value
        } catch {
            pinfo(
                "    Failed '\(message)' -> [\(singleton)]: error: \(error)",
                file: file,
                line: line
            )
            throw error
        }
    }

    internal func makeSingletonNode(_ name: String, port: Int, minimumMembers: Int) async -> ClusterSystem {
        await self.setUpNode(name) { settings in
            settings.endpoint.port = port
            settings.autoLeaderElection = .lowestReachable(minNumberOfMembers: minimumMembers)
            settings += ClusterSingletonPlugin()
        }
    }

    internal func hostSingleton(
        on system: ClusterSystem,
        name: String,
        settings: ClusterSingletonSettings,
        greeting: String
    ) async throws -> TheSingleton {
        try await system.singleton.host(name: name, settings: settings) { actorSystem in
            TheSingleton(greeting: greeting, actorSystem: actorSystem)
        }
    }

    internal func stashedGreeting(
        singleton: TheSingleton,
        greetingName: String,
        expectedPrefix: String
    ) -> (@Sendable () async throws -> SingletonStashTaskResult) {
        {
            let reply: String = try await singleton.greet(name: greetingName)
            reply.shouldStartWith(prefix: expectedPrefix)
            return .remoteCall
        }
    }

    internal func sendGreetingsUntilCancelled(
        singleton: TheSingleton,
        greetingName: String
    ) -> Task<[String], any Error> {
        Task {
            try await withThrowingTaskGroup(of: String.self) { group in
                var attempt: Int = 0
                for await _ in AsyncTimerSequence.repeating(every: .seconds(1), clock: .continuous) {
                    attempt += 1
                    let message: String = "\(greetingName) (\(attempt))"
                    group.addTask {
                        pnote(
                            "  Sending: '\(message)' -> [\(singleton)] (it may be terminated/not-re-pointed yet)",
                            file: #fileID,
                            line: #line
                        )
                        return try await Self.greetingReply(
                            singleton: singleton,
                            message: message,
                            file: #fileID,
                            line: #line
                        )
                    }
                }
                var replies: [String] = []
                for try await reply in group {
                    replies.append(reply)
                }
                return replies
            }
        }
    }

    internal func assertDeliveredGreetings(_ replies: [String], greetingName: String) throws {
        let firstReply: String = try XCTUnwrap(replies.first)
        firstReply.shouldStartWith(prefix: "Hello-4 \(greetingName)")
        if firstReply.starts(with: "Hello-4 \(greetingName) (1)!") {
            pinfo("  No messages were lost! Total \(replies.count) deliveries.", file: #fileID, line: #line)
        } else {
            pinfo("  Initial messages may have been lost, delivered message: \(firstReply)", file: #fileID, line: #line)
        }
    }

    /// Retries greetings because a handover can lose an in-flight message.
    internal func assertSingletonRequestReply(
        _ system: ClusterSystem,
        singleton: TheSingleton,
        greetingName: String,
        expectedPrefix: String
    ) async throws {
        let testKit: ActorTestKit = self.testKit(system)
        var attempts: Int = 0
        try await testKit.eventually(within: .seconds(10)) {
            attempts += 1
            do {
                let reply: String = try await RemoteCall.with(timeout: .seconds(1)) {
                    try await singleton.greet(name: greetingName)
                }
                reply.shouldStartWith(prefix: expectedPrefix)
            } catch {
                throw TestError(
                    """
                    Received no reply from singleton [\(singleton)] while sending from \
                    [\(system.cluster.node.endpoint)], perhaps request was lost. \
                    Sent greeting [\(greetingName)] and expected prefix: [\(expectedPrefix)] \
                    (attempts: \(attempts))
                    """
                )
            }
        }
    }

    internal func assertInitialSingletonReplies(
        first: (system: ClusterSystem, singleton: TheSingleton),
        second: (system: ClusterSystem, singleton: TheSingleton),
        third: (system: ClusterSystem, singleton: TheSingleton)
    ) async throws {
        try await self.assertSingletonRequestReply(
            first.system,
            singleton: first.singleton,
            greetingName: "Alice",
            expectedPrefix: "Hello-1 Alice!"
        )
        try await self.assertSingletonRequestReply(
            second.system,
            singleton: second.singleton,
            greetingName: "Bob",
            expectedPrefix: "Hello-1 Bob!"
        )
        try await self.assertSingletonRequestReply(
            third.system,
            singleton: third.singleton,
            greetingName: "Charlie",
            expectedPrefix: "Hello-1 Charlie!"
        )
    }

    internal func assertSingletonLeadershipHandover(
        first: ClusterSystem,
        second: (system: ClusterSystem, singleton: TheSingleton),
        third: (system: ClusterSystem, singleton: TheSingleton),
        fourth: ClusterSystem
    ) async throws {
        let firstNode: Cluster.Node = first.cluster.node
        first.cluster.leave()

        // Make sure that `second` and `third` see `first` as down and become leader-less
        try await self.assertMemberStatus(on: second.system, node: firstNode, is: .down, within: .seconds(10))
        try await self.assertMemberStatus(on: third.system, node: firstNode, is: .down, within: .seconds(10))

        try self.testKit(second.system).eventually(within: .seconds(10)) {
            try self.assertLeaderNode(on: second.system, is: nil)
            try self.assertLeaderNode(on: third.system, is: nil)
        }
        pinfo("Endpoint \(firstNode) left cluster...", file: #fileID, line: #line)

        // `fourth` will become the new leader and singleton
        pinfo("Endpoint \(fourth.cluster.node) joining cluster...", file: #fileID, line: #line)
        fourth.cluster.join(endpoint: second.system.cluster.node.endpoint)
        let start: ContinuousClock.Instant = ContinuousClock.Instant.now

        // No leader so singleton is not available, messages sent should be stashed

        let ref2Task: Task<[String], any Error> = sendGreetingsUntilCancelled(
            singleton: second.singleton,
            greetingName: "Bob"
        )
        let ref3Task: Task<[String], any Error> = sendGreetingsUntilCancelled(
            singleton: second.singleton,
            greetingName: "Charlie"
        )

        try await self.ensureNodes(
            .operational,
            nodes: third.system.cluster.node,
            fourth.cluster.node,
            on: second.system,
            within: .seconds(10)
        )
        let members: [Cluster.Node] = [
            fourth.cluster.node,
            second.system.cluster.node,
            third.system.cluster.node,
        ]
        pinfo(
            "Fourth node joined; members: \(members)",
            file: #fileID,
            line: #line
        )

        ref2Task.cancel()
        ref3Task.cancel()

        let got2: [String] = try await ref2Task.value
        pinfo("Received replies (by \(second.singleton)) from singleton: \(got2)", file: #fileID, line: #line)

        try assertDeliveredGreetings(got2, greetingName: "Bob")

        let got3: [String] = try await ref3Task.value
        pinfo("Received replies (by \(third.singleton)) from singleton: \(got3)", file: #fileID, line: #line)

        try assertDeliveredGreetings(got3, greetingName: "Charlie")

        let stop: ContinuousClock.Instant = ContinuousClock.Instant.now
        pinfo("Singleton re-pointing took: \((stop - start).prettyDescription)", file: #fileID, line: #line)

        pinfo("Nodes communicated successfully with singleton on [fourth]", file: #fileID, line: #line)
    }

    internal func assertClusterTaskFinishedFirst(
        _ group: inout ThrowingTaskGroup<SingletonStashTaskResult, any Error>
    ) async throws {
        var taskTypes: [SingletonStashTaskResult] = []
        for try await taskType in group {
            taskTypes.append(taskType)
        }
        guard taskTypes.first == .cluster else {
            throw TestError("Received reply to remote call reply before singleton is allocated")
        }
    }
}
