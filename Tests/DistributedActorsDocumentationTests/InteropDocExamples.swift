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
import DistributedCluster
import NIO
import XCTest

@testable import DistributedActorsTestKit

internal final class InteropDocExamples: SingleClusterSystemXCTestCase {
    private func example_asyncOp_sendResult_dispatch() async throws {
        // tag::message_greetings[]
        enum Messages: NotActuallyCodableMessage {
            case string(String)
        }
        // end::message_greetings[]

        let system: ClusterSystem = self.system

        let behavior: Behavior<Messages> = .receiveMessage { _ in
            // ...
            .same
        }

        func someComputation() -> String {
            "test"
        }

        // tag::asyncOp_sendResult_dispatch[]
        let ref: ActorRef<Messages> = try system.spawn(.anonymous, behavior)  // <1>

        DispatchQueue.global().async {  // <2>
            let result: String = someComputation()  // <3>

            ref.tell(.string(result))  // <4>
        }
        // end::asyncOp_sendResult_dispatch[]
        _ = behavior  // avoid not-used warning
    }

    private func example_asyncOp_sendResult_insideActor(
        fetchDataAsync: @escaping @Sendable (@escaping @Sendable (String) -> Void) -> Void
    ) async throws {
        // tag::asyncOp_sendResult_insideActor_enum_Messages[]
        enum Messages: NotActuallyCodableMessage {
            case fetchData
            case result(String)
        }
        // end::asyncOp_sendResult_insideActor_enum_Messages[]

        let system: ClusterSystem = self.system

        // tag::asyncOp_sendResult_insideActor[]
        let behavior: Behavior<Messages> = .receive { context, message in
            switch message {
            case .fetchData:
                let myself: ActorRef<Messages> = context.myself
                fetchDataAsync { result in  // <1>
                    // beware to NOT touch any mutable actor state as such access can
                    // (and will) result in concurrent access; all access must be
                    // serialized by executing on the actor's thread -- thus any
                    // actions must be performed in reaction to the .result message,
                    // and not earlier
                    myself.tell(.result(result))  // <2>
                }

            case .result(let res):
                print("Received result: \(res)")  // <3>
            }
            return .same
        }
        // end::asyncOp_sendResult_insideActor[]
        let ref: ActorRef<Messages> = try system.spawn(.anonymous, behavior)

        // tag::asyncOp_sendResult_insideActor_external_api[]
        ref.tell(.result("foo"))
        // end::asyncOp_sendResult_insideActor_external_api[]
    }

    private func example_asyncOp_onResultAsync() async {
        struct User {}

        // tag::asyncOp_onResultAsync_enum_Messages[]
        enum Messages: NotActuallyCodableMessage {
            case lookupUser(name: String, recipient: ActorRef<LookupResponse>)
        }

        enum LookupResponse: NotActuallyCodableMessage {
            case user(User)
            case unknownUser(name: String)
            case lookupFailed(Error)
        }
        // end::asyncOp_onResultAsync_enum_Messages[]

        let system: ClusterSystem = self.system

        let eventLoopGroup: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop: EventLoop = eventLoopGroup.next()
        func fetchUser(_: String) -> EventLoopFuture<User?> {
            eventLoop.makeSucceededFuture(nil)
        }

        // tag::asyncOp_onResultAsync[]
        let behavior: Behavior<Messages> = .setup { context in
            .receiveMessage { message in
                switch message {
                case let .lookupUser(name, replyTo):
                    let userFuture: EventLoopFuture<User?> = fetchUser(name)  // <3>

                    context.onResultAsync(of: userFuture, timeout: .seconds(5)) { result in  // <4>
                        switch result {
                        case .success(.some(let user)):  // <5>
                            replyTo.tell(.user(user))

                        case .success(.none):  // <6>
                            replyTo.tell(.unknownUser(name: name))

                        case .failure(let error):  // <7>
                            replyTo.tell(.lookupFailed(error))
                        }

                        return .same
                    }
                }

                return .same
            }
        }
        // end::asyncOp_onResultAsync[]

        _ = behavior
    }

    private func example_asyncOp_awaitResult() async {
        // tag::asyncOp_awaitResult_enum_Messages[]
        enum Message: NotActuallyCodableMessage {
            case addPrefix(string: String, recipient: ActorRef<String>)
        }
        // end::asyncOp_awaitResult_enum_Messages[]

        let system: ClusterSystem = self.system

        let eventLoopGroup: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop: EventLoop = eventLoopGroup.next()
        func fetchDataAsync() -> EventLoopFuture<String> {
            eventLoop.makeSucceededFuture("success")
        }

        // tag::asyncOp_awaitResult[]
        let behavior: Behavior<Message> = .setup { context in
            let future: EventLoopFuture<String> = fetchDataAsync()  // <1>
            return context.awaitResult(of: future, timeout: .milliseconds(100)) { result in  // <2>
                switch result {
                case .success(let necessaryPrefix):
                    return prefixer(prefix: necessaryPrefix)  // <3>

                case .failure(let error):
                    throw error  // <4>
                }
            }
        }

        func prefixer(prefix: String) -> Behavior<Message> {
            .receiveMessage { message in
                switch message {
                case let .addPrefix(string, recipient):
                    recipient.tell("\(prefix): \(string)")
                    return .same
                }
            }
        }
        // end::asyncOp_awaitResult[]
        _ = behavior  // avoids warning: unused variable
    }

    private func example_asyncOp_awaitResultThrowing() async {
        enum Message: NotActuallyCodableMessage {
            case addPrefix(string: String, recipient: ActorRef<String>)
        }

        let system: ClusterSystem = self.system

        let eventLoopGroup: MultiThreadedEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop: EventLoop = eventLoopGroup.next()
        func fetchDataAsync() -> EventLoopFuture<String> {
            eventLoop.makeSucceededFuture("success")
        }

        func prefixer(prefix: String) -> Behavior<Message> {
            .receiveMessage { message in
                switch message {
                case let .addPrefix(string, recipient):
                    recipient.tell("\(prefix): \(string)")
                    return .same
                }
            }
        }

        // tag::asyncOp_awaitResultThrowing[]
        let behavior: Behavior<Message> = .setup { context in
            let future: EventLoopFuture<String> = fetchDataAsync()  // <1>
            return context.awaitResultThrowing(of: future, timeout: .milliseconds(100)) { prefix in  // <2>
                prefixer(prefix: prefix)
            }
        }
        // end::asyncOp_awaitResultThrowing[]
        _ = behavior  // silence not-used warning
    }
}
