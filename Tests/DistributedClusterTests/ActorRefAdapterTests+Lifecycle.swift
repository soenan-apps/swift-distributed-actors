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

import DistributedActorsTestKit
import Foundation
import XCTest

@testable import DistributedCluster

extension ActorRefAdapterTests {
    internal func test_adapter_shouldAllowDroppingMessages() throws {
        let probe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(expecting: ActorRef<String>.self)

        let pAdapted: ActorTestProbe<Int> = self.testKit.makeTestProbe(expecting: Int.self)

        let behavior: Behavior<Int> = .setup { context in
            probe.tell(
                context.messageAdapter { message in
                    if message.contains("drop") {
                        return nil
                    }
                    return message.count
                }
            )
            return .receiveMessage { stringLength in
                pAdapted.tell(stringLength)
                return .same
            }
        }

        try system.spawn(.anonymous, behavior)

        let adaptedRef: ActorRef<String> = try probe.expectMessage()

        probe.watch(adaptedRef)

        adaptedRef.tell("hi")
        adaptedRef.tell("drop")
        adaptedRef.tell("hello")
        adaptedRef.tell("drop-hello")

        try pAdapted.expectMessage("hi".count)
        try pAdapted.expectMessage("hello".count)
        try pAdapted.expectNoMessage(for: .milliseconds(10))
    }

    internal func test_adaptedRef_shouldShareTheSameLifecycleAsItsActor() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let receiveRefProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            expecting: ActorRef<String>.self
        )

        let strategy: SupervisionStrategy = SupervisionStrategy.restart(atMost: 5, within: .seconds(5))

        let behavior: Behavior<LifecycleTestMessage> = .setup { context in
            .receiveMessage { closureArgument in
                switch closureArgument {
                case .crash:
                    throw Boom("")

                case .createAdapter(let replyTo):
                    replyTo.tell(context.messageAdapter { .message("\($0)") })
                    return .same

                case .stop:
                    return .stop

                case .message(let string):
                    probe.tell("received:\(string)")
                    return .same
                }
            }
        }

        let ref: ActorRef<LifecycleTestMessage> = try system.spawn(
            .anonymous,
            behavior,
            props: .supervision(
                strategy: strategy
            )
        )

        ref.tell(.createAdapter(replyTo: receiveRefProbe.ref))
        let adaptedRef: ActorRef<String> = try receiveRefProbe.expectMessage()

        probe.watch(ref)
        probe.watch(adaptedRef)

        ref.tell(.crash)

        try probe.expectNoTerminationSignal(for: .milliseconds(100))

        adaptedRef.tell("test")
        try probe.expectMessage("received:test")

        ref.tell(.stop)
        try probe.expectTerminatedInAnyOrder([ref.asAddressable, adaptedRef.asAddressable])
    }

    internal func test_adaptedRef_newAdapterShouldReplaceOld() throws {
        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)
        let receiveRefProbe: ActorTestProbe<ActorRef<String>> = self.testKit.makeTestProbe(
            expecting: ActorRef<String>.self
        )

        let strategy: SupervisionStrategy = SupervisionStrategy.restart(atMost: 5, within: .seconds(5))

        let behavior: Behavior<LifecycleTestMessage> = .setup { context in
            var adapterCounter: Int = 0
            return .receiveMessage { closureArgument in
                switch closureArgument {
                case .createAdapter(let replyTo):
                    let counter: Int = adapterCounter
                    replyTo.tell(context.messageAdapter { .message("adapter-\(counter):\($0)") })
                    adapterCounter += 1
                    return .same

                case .message(let string):
                    probe.tell("received:\(string)")
                    return .same

                default:
                    return .same
                }
            }
        }

        let ref: ActorRef<LifecycleTestMessage> = try system.spawn(
            .anonymous,
            behavior,
            props: .supervision(
                strategy: strategy
            )
        )

        ref.tell(.createAdapter(replyTo: receiveRefProbe.ref))
        let adaptedRef: ActorRef<String> = try receiveRefProbe.expectMessage()

        adaptedRef.tell("test")
        try probe.expectMessage("received:adapter-0:test")

        ref.tell(.createAdapter(replyTo: receiveRefProbe.ref))
        let adaptedRef2: ActorRef<String> = try receiveRefProbe.expectMessage()

        adaptedRef2.tell("test")
        try probe.expectMessage("received:adapter-1:test")

        // existing ref stays valid, but uses new adapter
        adaptedRef.tell("test")
        try probe.expectMessage("received:adapter-1:test")
    }

    internal func test_adaptedRef_useSpecificEnoughAdapterMostRecentlySet() throws {
        class TopExample: NotActuallyCodableMessage {}
        class BottomExample: TopExample {}

        let probe: ActorTestProbe<String> = self.testKit.makeTestProbe(expecting: String.self)

        let probeTop: ActorTestProbe<ActorRef<TopExample>> = self.testKit.makeTestProbe(
            expecting: ActorRef<TopExample>.self
        )
        let probeBottom: ActorTestProbe<ActorRef<BottomExample>> = self.testKit.makeTestProbe(
            expecting: ActorRef<BottomExample>.self
        )

        let behavior: Behavior<LifecycleTestMessage> = .setup { context in
            let topRef: ActorRef<TopExample> = context.messageAdapter { .message("adapter-top:\($0)") }
            probeTop.tell(topRef)
            let bottomRef: ActorRef<BottomExample> = context.messageAdapter { .message("adapter-bottom:\($0)") }
            probeBottom.tell(bottomRef)

            return .receiveMessage { closureArgument in
                switch closureArgument {
                case .message(let string):
                    probe.tell("received:\(string)")
                    return .same

                default:
                    return .same
                }
            }
        }

        try system.spawn(.anonymous, behavior)

        let topRef: ActorRef<TopExample> = try probeTop.expectMessage()
        let bottomRef: ActorRef<BottomExample> = try probeBottom.expectMessage()

        let top: TopExample = TopExample()
        let bottom: BottomExample = BottomExample()

        topRef.tell(top)
        try probe.expectMessage("received:adapter-top:\(top)")

        bottomRef.tell(bottom)
        try probe.expectMessage("received:adapter-bottom:\(bottom)")

        topRef.tell(bottom)
        try probe.expectMessage("received:adapter-bottom:\(bottom)")
    }
}
