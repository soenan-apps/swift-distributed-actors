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

// end::imports[]

internal class SupervisionDocExamples {
    internal lazy var system: ClusterSystem = undefined(hint: "Examples, not intended to be run")

    internal func supervise_props() throws {
        let greeterBehavior: Behavior<String> = undefined()
        let context: ActorContext<String> = undefined()

        // tag::supervise_props[]
        let props: Props = Props()  // <1>
            .supervision(strategy: .restart(atMost: 2, within: .seconds(1)))  // <2>
        // potentially more props configuration here ...

        let greeterRef: ActorRef<String> = try context.spawn(
            "greeter",
            greeterBehavior,
            props: props  // <3>
        )
        // end::supervise_props[]
        _ = greeterRef
    }

    internal func supervise_inline() throws {
        let greeterBehavior: Behavior<String> = undefined()
        let context: ActorContext<String> = undefined()

        // tag::supervise_inline[]
        let greeterRef: ActorRef<String> = try context.spawn(
            "greeter",
            greeterBehavior,
            props: .supervision(strategy: .restart(atMost: 2, within: .seconds(1)))  // <1>
        )
        // end::supervise_inline[]
        _ = greeterRef
    }

    internal func supervise_full_example() throws {
        // tag::supervise_full_example[]
        enum GreeterError: Error {
            case doesNotLike(name: String)
        }

        func greeterBehavior(friends: [String]) -> Behavior<String> {
            .receive { context, name in
                guard friends.contains(name) else {
                    context.log.warning("Overreacting to \(name)... Letting it crash!")
                    throw GreeterError.doesNotLike(name: name)
                }

                context.log.info("Hello \(name)!")
                return .same
            }
        }
        // end::supervise_full_example[]

        // tag::supervise_full_usage[]
        let friends: [String] = ["Alice", "Bob", "Caplin"]

        let greeterRef: ActorRef<String> = try system.spawn(
            "greeter",
            greeterBehavior(friends: friends),
            props: .supervision(strategy: .restart(atMost: 5, within: .seconds(1)))
        )

        greeterRef.tell("Alice")  // ok!
        greeterRef.tell("Boom!")  // crash!
        // greeter is restarted (1st failure / out of 5 within 1s allowed ones)
        greeterRef.tell("Bob")  // ok!
        greeterRef.tell("Boom Boom!")  // crash!
        // greeter is restarted (2nd failure / out of 5 within 1s allowed ones)
        greeterRef.tell("Caplin")  // ok!
        // end::supervise_full_usage[]
    }

    internal func supervise_fault_example() throws {
        // tag::supervise_fault_example[]
        typealias Name = String
        typealias LikedFruit = String

        func favouriteFruitBehavior(_ whoLikesWhat: [Name: LikedFruit]) -> Behavior<String> {
            .receive { context, name in
                guard let likedFruit: LikedFruit = whoLikesWhat[name] else {
                    preconditionFailure("No favorite fruit registered for \(name)")
                }

                context.log.info("\(name) likes [\(likedFruit)]!")
                return .same
            }
        }
        // end::supervise_fault_example[]

        // tag::supervise_fault_usage[]
        let whoLikesWhat: [Name: LikedFruit] = [
            "Alice": "Apples",
            "Bob": "Bananas",
            "Caplin": "Cucumbers",
        ]

        let greeterRef: ActorRef<String> = try system.spawn(
            "favFruit",
            favouriteFruitBehavior(whoLikesWhat),
            props: .supervision(strategy: .restart(atMost: 5, within: .seconds(1)))
        )

        greeterRef.tell("Alice")  // ok!
        greeterRef.tell("Boom!")  // crash!
        // greeter is restarted
        greeterRef.tell("Bob")  // ok!
        greeterRef.tell("Boom Boom!")  // crash!
        greeterRef.tell("Caplin")  // ok!
        // end::supervise_fault_usage[]
    }
}
