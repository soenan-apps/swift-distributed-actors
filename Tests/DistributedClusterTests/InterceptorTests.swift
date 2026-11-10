// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed
import DistributedActorsTestKit
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

internal final class ShoutingInterceptor: Interceptor<String> {
    internal let probe: ActorTestProbe<String>?

    internal init(probe: ActorTestProbe<String>? = nil) {
        self.probe = probe
    }

    override internal func interceptMessage(
        target: Behavior<String>,
        context: ActorContext<String>,
        message: String
    ) throws -> Behavior<String> {
        self.probe?.tell("from-interceptor:\(message)")
        return try target.interpretMessage(context: context, message: message + "!")
    }

    override internal func isSame(as _: Interceptor<String>) -> Bool {
        false
    }
}

internal final class TerminatedInterceptor<Message: Codable>: Interceptor<Message> {
    internal let probe: ActorTestProbe<Signals.Terminated>

    internal init(probe: ActorTestProbe<Signals.Terminated>) {
        self.probe = probe
    }

    override internal func interceptSignal(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        signal: Signal
    ) throws -> Behavior<Message> {
        switch signal {
        case let terminated as Signals.Terminated:
            self.probe.tell(terminated)  // we forward all termination signals to someone

        case is Signals.PostStop:
            ()  // ok

        default:
            fatalError("Other signal: \(signal)")
            ()
        }
        return try target.interpretSignal(context: context, signal: signal)
    }
}

private distributed actor Greeter {
    typealias ActorSystem = ClusterSystem

    let greeting: String

    init(actorSystem: ActorSystem, greeting: String) {
        self.actorSystem = actorSystem
        self.greeting = greeting
    }

    distributed func greet() -> String {
        self.greeting
    }

    distributed func greetThrow(codable: Bool) throws -> String {
        if codable {
            throw InterceptorGreeterCodableError()
        }
        throw GreeterNonCodableError()
    }

    distributed func greet(delayNanos: UInt64) async throws -> String {
        try await Task.sleep(nanoseconds: delayNanos)
        return self.greet()
    }

    distributed func muted() {
        self.actorSystem.log.info("Muted greeting: \(self.greeting)")
    }

    distributed func mutedThrow(codable: Bool) throws {
        if codable {
            throw InterceptorGreeterCodableError()
        }
        throw GreeterNonCodableError()
    }

    distributed func muted(delayNanos: UInt64) async throws {
        try await Task.sleep(nanoseconds: delayNanos)
        self.muted()
    }
}

private struct GreeterRemoteCallInterceptor: RemoteCallInterceptor {
    let system: ClusterSystem
    let greeter: Greeter

    func interceptRemoteCall<Act, Err, Res>(
        on _: Act,

        target: RemoteCallTarget,

        invocation: inout ClusterSystem.InvocationEncoder,

        throwing _: Err.Type,

        returning _: Res.Type
    ) async throws -> Res
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error,
        Res: Codable {
        guard let interceptedActor = self.greeter as? Act else {
            throw GreeterRemoteCallInterceptorError()
        }

        guard
            let interceptedResult =
                (try await withCheckedThrowingContinuation { (childContext: CheckedContinuation<Any, Error>) in
                    Task { [invocation] in
                        do {
                            var directDecoder: ClusterInvocationDecoder = ClusterInvocationDecoder(
                                system: greeter.actorSystem,
                                invocation: invocation
                            )
                            let directReturnHandler: ClusterInvocationResultHandler = ClusterInvocationResultHandler(
                                directReturnContinuation: childContext
                            )

                            try await greeter.actorSystem.executeDistributedTarget(
                                on: interceptedActor,

                                target: target,

                                invocationDecoder: &directDecoder,

                                handler: directReturnHandler
                            )
                        } catch {
                            childContext.resume(throwing: error)
                        }
                    }
                }) as? Res
        else {
            throw GreeterRemoteCallInterceptorError()
        }
        return interceptedResult
    }

    func interceptRemoteCallVoid<Act, Err>(
        on _: Act,

        target: RemoteCallTarget,

        invocation: inout ClusterSystem.InvocationEncoder,

        throwing _: Err.Type
    ) async throws
    where
        Act: DistributedActor,
        Act.ID == ActorID,
        Err: Error {
        guard let interceptedActor = self.greeter as? Act else {
            throw GreeterRemoteCallInterceptorError()
        }

        _ = try await withCheckedThrowingContinuation { (childContext: CheckedContinuation<Any, Error>) in
            Task { [invocation] in
                do {
                    var directDecoder: ClusterInvocationDecoder = ClusterInvocationDecoder(
                        system: greeter.actorSystem,
                        invocation: invocation
                    )
                    let directReturnHandler: ClusterInvocationResultHandler = ClusterInvocationResultHandler(
                        directReturnContinuation: childContext
                    )

                    try await greeter.actorSystem.executeDistributedTarget(
                        on: interceptedActor,

                        target: target,

                        invocationDecoder: &directDecoder,

                        handler: directReturnHandler
                    )
                } catch {
                    childContext.resume(throwing: error)
                }
            }
        }
    }
}

private struct InterceptorGreeterCodableError: Error, Codable {}
private struct GreeterNonCodableError: Error {}
private struct GreeterRemoteCallInterceptorError: Error, Codable {}

internal final class InterceptorTests: SingleClusterSystemXCTestCase {
    internal class SignalToStringInterceptor<Message: Codable>: Interceptor<Message> {
        internal let probe: ActorTestProbe<String>

        internal init(_ probe: ActorTestProbe<String>) {
            self.probe = probe
        }

        override internal func interceptSignal(
            target: Behavior<Message>,
            context: ActorContext<Message>,
            signal: Signal
        ) throws -> Behavior<Message> {
            self.probe.tell("intercepted:\(signal)")
            return try target.interpretSignal(context: context, signal: signal)
        }
    }

    internal func test_remoteCall_interceptor() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.enabled = true
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.enabled = true
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let otherGreeter: Greeter = Greeter(actorSystem: local, greeting: "HI!!!")
        let localGreeter: Greeter = try system.interceptCalls(
            to: Greeter.self,

            metadata: ActorMetadata(),

            interceptor: GreeterRemoteCallInterceptor(system: local, greeter: otherGreeter)
        )

        let value: String = try await shouldNotThrow {
            try await localGreeter.greet()
        }
        value.shouldEqual("HI!!!")
    }

    internal func test_remoteCallVoid_interceptor() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.enabled = true
        }
        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.enabled = true
        }
        local.cluster.join(endpoint: remote.cluster.endpoint)

        let otherGreeter: Greeter = Greeter(actorSystem: local, greeting: "HI!!!")
        let localGreeter: Greeter = try shouldNotThrow {
            try system.interceptCalls(
                to: Greeter.self,

                metadata: ActorMetadata(),

                interceptor: GreeterRemoteCallInterceptor(system: local, greeter: otherGreeter)
            )
        }

        try await shouldNotThrow {
            try await localGreeter.muted()
        }
        try self.capturedLogs(of: local).awaitLogContaining(self.testKit(local), text: "Muted greeting: HI!!!")
    }

    // Legacy interceptor API tests -----------------------------------------------------------------------------------

    internal func test_interceptor_shouldConvertMessages() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let interceptor: ShoutingInterceptor = ShoutingInterceptor()

        let forwardToProbe: Behavior<String> = .receiveMessage { message in
            probeForTest.tell(message)
            return .same
        }

        let ref: ActorRef<String> = try system.spawn(
            "theWallsHaveEars",

            .intercept(behavior: forwardToProbe, with: interceptor)
        )

        for index in 0...10 {
            ref.tell("hello:\(index)")
        }

        for index in 0...10 {
            try probeForTest.expectMessage("hello:\(index)!")
        }
    }

    internal func test_interceptor_shouldSurviveDeeplyNestedInterceptors() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()
        let index: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let makeStringsLouderInterceptor: ShoutingInterceptor = ShoutingInterceptor(probe: index)

        // just like in the movie "Inception"
        func interceptionInceptionBehavior(currentDepth depth: Int, stopAt limit: Int) -> Behavior<String> {
            let behavior: Behavior<String>
            if depth < limit {
                // add another "setup layer"
                behavior = interceptionInceptionBehavior(currentDepth: depth + 1, stopAt: limit)
            } else {
                behavior = .receiveMessage { msg in
                    probeForTest.tell("received:\(msg)")
                    return .stop
                }
            }

            return .intercept(behavior: behavior, with: makeStringsLouderInterceptor)
        }

        let depth: Int = 50
        let ref: ActorRef<String> = try system.spawn(
            "theWallsHaveEars",

            interceptionInceptionBehavior(currentDepth: 0, stopAt: depth)
        )

        ref.tell("hello")

        try probeForTest.expectMessage("received:hello!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
        for innerIndex in 0...depth {
            let messageForTest: String = "from-interceptor:hello\(String(repeating: "!", count: innerIndex))"
            try index.expectMessage(messageForTest)
        }
    }

    internal func test_interceptor_shouldRemainWhenReturningStoppingWithPostStop() throws {
        let probeForTest: ActorTestProbe<String> = self.testKit.makeTestProbe()

        let behavior: Behavior<String> = .receiveMessage { _ in
            .stop { _ in
                probeForTest.tell("postStop")
            }
        }

        let interceptedBehavior: Behavior<String> = .intercept(
            behavior: behavior,
            with: SignalToStringInterceptor(
                probeForTest
            )
        )

        let ref: ActorRef<String> = try system.spawn(.anonymous, interceptedBehavior)
        probeForTest.watch(ref)
        ref.tell("test")

        try probeForTest.expectMessage("intercepted:PostStop()")
        try probeForTest.expectMessage("postStop")
        try probeForTest.expectTerminated(ref)
    }
}
