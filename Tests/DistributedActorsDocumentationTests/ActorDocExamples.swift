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

// tag::imports[]

import DistributedCluster
import XCTest

@testable import DistributedActorsTestKit

// end::imports[]

// tag::suggested_props_pattern[]
internal enum ExampleWorker {
    internal static var suggested: (Behavior<WorkerMessages>, Props) {
        (behavior, Self.props)
    }

    internal static var behavior: Behavior<WorkerMessages> = .receive { context, _ in
        context.log.info("Work, work!")
        return .same
    }

    internal static var props: Props = .init().dispatcher(.pinnedThread)
}

internal enum WorkerMessages: String, Codable {
    case something = "something"
}

internal func run(system: ClusterSystem) throws {
    let (behavior, props): (Behavior<WorkerMessages>, Props) = ExampleWorker.suggested
    try system.spawn("heavy-worker", behavior, props: props)
}

// end::suggested_props_pattern[]
internal final class ActorDocExamples: XCTestCase {
    // tag::message_greetings[]
    private enum Greetings: NotActuallyCodableMessage {
        case greet(name: String)
        case greeting(String)
    }

    private enum LineByLineData {
        case line(String)
        case endOfFile
    }

    // end::message_greetings[]

    // tag::stop_myself_refactored[]
    private static func stopForTerminal(_ data: LineByLineData) -> Behavior<String> {
        switch data {
        case .endOfFile:
            return .stop

        default:
            return .same
        }
    }
    // end::stop_myself_refactored[]
    private func example_receive_behavior() {
        // tag::receive_behavior[]
        let behavior: Behavior<Greetings> = .receive { _, message in  // <1>
            print("Received \(message)")  // <2>
            return .same  // <3>
        }
        // end::receive_behavior[]
        _ = behavior  // silence not-used warning
    }

    private func example_receiveMessage_behavior() {
        // tag::receiveMessage_behavior[]
        let behavior: Behavior<Greetings> = .receiveMessage { message in  // <1>
            print("Received \(message)")  // <2>
            return .same  // <3>
        }
        // end::receiveMessage_behavior[]
        _ = behavior  // silence not-used warning
    }

    private func example_spawn_tell() async throws {
        // tag::spawn[]
        let system: ClusterSystem = await ClusterSystem("ExampleSystem")  // <1>

        let greeterBehavior: Behavior<String> = .receiveMessage { name in  // <2>
            print("Hello \(name)!")
            return .same
        }

        let greeterRef: ActorRef<String> = try system.spawn("greeter", greeterBehavior)  // <3>
        // end::spawn[]

        // tag::tell_1[]
        // greeterRef: ActorRef<String>
        greeterRef.tell("Caplin")  // <1>

        // prints: "Hello Caplin!"
        // end::tell_1[]
    }

    private func example_stop_myself() {
        // tag::stop_myself_1[]
        let lineHandling: Behavior<String> = .receive { _, _ in
            let data: LineByLineData = readLine().map(LineByLineData.line) ?? .endOfFile  // <1>
            // do things with `data`...

            // and then...
            switch data {
            case .endOfFile:
                return .stop  // <2>

            default:
                return .same
            }
        }
        // end::stop_myself_1[]
        _ = lineHandling  // silence not used warning
    }

    private func example_stop_myself_refactored() {
        // tag::stop_myself_refactored[]
        let lineHandling: Behavior<String> = .receive { _, _ in
            let data: LineByLineData = readLine().map(LineByLineData.line) ?? .endOfFile
            // do things with `data`...

            // and then...
            return Self.stopForTerminal(data)
        }
        // end::stop_myself_refactored[]
        _ = lineHandling  // silence not-used warning
    }

    private func example_props() {
        // tag::props_example[]
        let props: Props = Props()
        // end::props_example[]
        _ = props  // silence not-used warning
    }

    private func example_props_inline() async throws {
        let behavior: Behavior<String> = .ignore
        let system: ClusterSystem = await ClusterSystem("ExampleSystem")

        // tag::props_inline[]
        let worker: ActorRef<String> = try system.spawn("worker", behavior, props: .dispatcher(.default))
        // end::props_inline[]
        _ = worker  // silence not-used warning
    }

    private func example_receptionist_register() {
        // tag::receptionist_register[]
        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "my-actor")  // <1>

        let behavior: Behavior<String> = .setup { context in
            context.receptionist.registerMyself(with: key, replyTo: nil)  // <2>

            return .receiveMessage { _ in
                // ...
                .same
            }
        }
        // end::receptionist_register[]

        _ = behavior
    }

    private func example_receptionist_lookup() async throws {
        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "my-actor")
        let system: ClusterSystem = await ClusterSystem("LookupExample")
        // tag::receptionist_lookup[]
        let response: ActorRef<Reception.Listing<ActorRef<String>>> = try system.spawn(
            "lookupResponse",
            .receiveMessage { listing in
                for ref in listing.refs {
                    ref.tell("Hello")
                }
                return .stop
            }
        )  // <1>
        system.actorRefReceptionist.lookup(key, replyTo: response, timeout: .seconds(1))

        // end::receptionist_lookup[]
    }

    private func example_receptionist_subscribe() {
        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "my-actor")
        // tag::receptionist_subscribe[]
        let behavior: Behavior<Reception.Listing<ActorRef<String>>> = .setup { context in
            context.system.actorRefReceptionist.subscribe(context.myself, to: key)  // <1>

            return .receiveMessage { listing in
                for ref in listing.refs {
                    ref.tell("Hello")
                }
                return .same
            }
        }
        // end::receptionist_subscribe[]

        _ = behavior
    }

    private func example_context_receptionist_subscribe() {
        let key: Reception.Key = Reception.Key(ActorRef<String>.self, id: "my-actor")
        // tag::context_receptionist_subscribe[]
        let behavior: Behavior<Reception.Listing<ActorRef<String>>> = .setup { context in
            context.system.actorRefReceptionist.subscribe(context.myself, to: key)  // <1>

            return .receiveMessage { listing in
                for ref in listing.refs {
                    ref.tell("Hello")
                }
                return .same
            }
        }
        // end::context_receptionist_subscribe[]

        _ = behavior
    }

    private func example_ask_outside() async throws {
        let system: ClusterSystem = await ClusterSystem("ExampleSystem")

        // tag::ask_outside[]
        struct Hello: Codable {
            let name: String
            let replyTo: ActorRef<String>
        }

        let greeterBehavior: Behavior<Hello> = .receiveMessage { message in
            message.replyTo.tell("Hello \(message.name)!")
            return .same
        }

        let greeter: ActorRef<Hello> = try system.spawn("greeter", greeterBehavior)

        let response: AskResponse<String> = greeter.ask(timeout: .seconds(1)) { replyTo in  // <1>
            Hello(name: "Anne", replyTo: replyTo)  // <2>
        }

        response.onComplete { result in _ = result }  // <3>
        // end::ask_outside[]
    }

    private func example_ask_inside() async throws {
        let system: ClusterSystem = await ClusterSystem("ExampleSystem")

        // tag::ask_inside[]
        struct Hello: Codable {
            let name: String
            let replyTo: ActorRef<String>
        }

        let greeterBehavior: Behavior<Hello> = .receiveMessage { message in
            message.replyTo.tell("Hello \(message.name)!")
            return .same
        }

        let greeter: ActorRef<Hello> = try system.spawn("greeter", greeterBehavior)

        let caplinBehavior: Behavior<Never> = .setup { context in
            let timeout: Duration = .seconds(1)

            let response: AskResponse<String> =  // <1>
                greeter.ask(timeout: timeout) { replyTo in
                    Hello(name: context.name, replyTo: replyTo)
                }

            func greeted() -> Behavior<Never> {
                .stop
            }

            return context.awaitResultThrowing(of: response, timeout: timeout) { (greeting: String) in  // <2>
                context.log.info("I've been greeted: \(greeting)")
                return .stop  // <3>
            }
        }

        try system.spawn("caplin", caplinBehavior)
        // end::ask_inside[]
    }
}
