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

internal struct WrappedString: Codable {
    internal let string: String
}

internal enum SerializationBehavior: String, Codable {
    case failDecoding = "failDecoding"
    case failEncoding = "failEncoding"
    case succeed = "succeed"
}

private struct SerializationTestMessage: Codable, CustomStringConvertible {
    internal enum CodingKeys: String, CodingKey {
        case fails = "fails"
    }

    let serializationBehavior: SerializationBehavior

    var description: String {
        "SerializationTestMessage"
    }

    init(serializationBehavior: SerializationBehavior) {
        self.serializationBehavior = serializationBehavior
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        guard try !container.decode(Bool.self, forKey: .fails) else {
            throw Boom("")
        }

        self.serializationBehavior = .succeed
    }

    func encode(to encoder: Encoder) throws {
        guard self.serializationBehavior != .failEncoding else {
            throw Boom("")
        }

        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.serializationBehavior == .failDecoding, forKey: .fails)
    }
}

private struct EchoTestMessage: Codable {
    let string: String
    let respondTo: ActorRef<String>
}

internal struct Boom: Error {
    internal let message: String

    internal init(_ message: String) {
        self.message = message
    }
}

internal final class RemoteMessagingClusteredTests: ClusteredActorSystemsXCTestCase {
    // TODO: This will start failing once we implement _mangledTypeName manifests
    internal func test_association_shouldStayAliveWhenMessageSerializationFailsOnReceivingSide() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.serialization.register(SerializationTestMessage.self)
            settings.serialization.register(EchoTestMessage.self)
        }

        let remote: ClusterSystem = await setUpNode("remote") { settings in
            // do not register SerializationTestMessage on purpose, we want it to fail when receiving
            settings.serialization.register(EchoTestMessage.self)
        }

        let probeOnRemote: ActorTestProbe<String> = self.testKit(remote).makeTestProbe(expecting: String.self)
        let nonCodableRefOnRemoteSystem: ActorRef<SerializationTestMessage> = try remote.spawn(
            "remoteAcquaintance1",
            .receiveMessage { message in
                probeOnRemote.tell("forwarded:\(message)")
                return .same
            }
        )

        let codableRefOnRemoteSystem: ActorRef<String> = try remote.spawn(
            "remoteAcquaintance2",
            .receiveMessage { message in
                probeOnRemote.tell("forwarded:\(message)")
                return .same
            }
        )

        local.cluster.join(endpoint: remote.cluster.node.endpoint)

        try assertAssociated(local, withExactly: remote.settings.bindNode)

        let nonCodableResolvedRef: ActorRef<SerializationTestMessage> =
            self.resolveRef(local, type: SerializationTestMessage.self, id: nonCodableRefOnRemoteSystem.id, on: remote)
        nonCodableResolvedRef.tell(SerializationTestMessage(serializationBehavior: .succeed))

        try probeOnRemote.expectNoMessage(for: .milliseconds(500))

        let codableResolvedRef: ActorRef<String> =
            self.resolveRef(local, type: String.self, id: codableRefOnRemoteSystem.id, on: remote)
        codableResolvedRef.tell("HELLO")

        try probeOnRemote.expectMessage("forwarded:HELLO")
    }

    internal func test_association_shouldStayAliveWhenMessageSerializationThrowsOnSendingSide() async throws {
        try await shouldNotThrow {
            let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
                settings.serialization.register(SerializationTestMessage.self)
                settings.serialization.register(EchoTestMessage.self)
            }

            let probeOnRemote: ActorTestProbe<String> = self.testKit(remote).makeTestProbe(expecting: String.self)
            let refOnRemoteSystem: ActorRef<SerializationTestMessage> = try remote.spawn(
                .anonymous,
                .receiveMessage { message in
                    probeOnRemote.tell("forwarded:\(message)")
                    return .same
                }
            )

            local.cluster.join(endpoint: remote.cluster.node.endpoint)

            try assertAssociated(local, withExactly: remote.settings.bindNode)

            let nonCodableResolvedRef: ActorRef<SerializationTestMessage> =
                self.resolveRef(local, type: SerializationTestMessage.self, id: refOnRemoteSystem.id, on: remote)
            nonCodableResolvedRef.tell(SerializationTestMessage(serializationBehavior: .failEncoding))

            try probeOnRemote.expectNoMessage(for: .milliseconds(100))

            nonCodableResolvedRef.tell(SerializationTestMessage(serializationBehavior: .succeed))
            try probeOnRemote.expectMessage("forwarded:SerializationTestMessage")
        }
    }

    internal func test_association_shouldStayAliveWhenMessageSerializationThrowsOnReceivingSide() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.serialization.register(SerializationTestMessage.self)
            settings.serialization.register(EchoTestMessage.self)
        }

        let probeOnRemote: ActorTestProbe<String> = self.testKit(remote).makeTestProbe(expecting: String.self)
        let nonCodableRefOnRemoteSystem: ActorRef<SerializationTestMessage> = try remote.spawn(
            .anonymous,
            .receiveMessage { message in
                probeOnRemote.tell("forwarded:\(message)")
                return .same
            }
        )

        local.cluster.join(endpoint: remote.cluster.node.endpoint)

        try assertAssociated(local, withExactly: remote.settings.bindNode)

        let nonCodableResolvedRef: ActorRef<SerializationTestMessage> =
            self.resolveRef(local, type: SerializationTestMessage.self, id: nonCodableRefOnRemoteSystem.id, on: remote)
        nonCodableResolvedRef.tell(SerializationTestMessage(serializationBehavior: .failDecoding))

        try probeOnRemote.expectNoMessage(for: .milliseconds(100))

        nonCodableResolvedRef.tell(SerializationTestMessage(serializationBehavior: .succeed))
        try probeOnRemote.expectMessage("forwarded:SerializationTestMessage")
    }

    internal func test_sendingToRefWithAddressWhichIsActuallyLocalAddress_shouldWork() async throws {
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.serialization.register(SerializationTestMessage.self)
            settings.serialization.register(EchoTestMessage.self)
        }

        let testKit: ActorTestKit = ActorTestKit(local)
        let probe: ActorTestProbe<String> = testKit.makeTestProbe(expecting: String.self)
        let localRef: ActorRef<String> = try local.spawn(
            "local",
            .receiveMessage { message in
                probe.tell("received:\(message)")
                return .same
            }
        )

        let localResolvedRefWithLocalAddress: ActorRef<String> =
            self.resolveRef(local, type: String.self, id: localRef.id, on: local)

        localResolvedRefWithLocalAddress.tell("hello")
        try probe.expectMessage("received:hello")
    }

    internal func test_remoteActors_echo() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.serialization.register(EchoTestMessage.self)
            settings.serialization.register(SerializationTestMessage.self)
            settings.serialization.register(EchoTestMessage.self)
        }

        let probe: ActorTestProbe<String> = self.testKit(local).makeTestProbe("X", expecting: String.self)

        let localRef: ActorRef<String> = try local.spawn(
            "localRef",
            .receiveMessage { message in
                probe.tell("response:\(message)")
                return .same
            }
        )

        let refOnRemoteSystem: ActorRef<EchoTestMessage> = try remote.spawn(
            "remoteAcquaintance",
            .receiveMessage { message in
                message.respondTo.tell("echo:\(message.string)")
                return .same
            }
        )

        local.cluster.join(endpoint: remote.cluster.node.endpoint)

        try assertAssociated(local, withExactly: remote.settings.bindNode)

        let remoteRef: ActorRef<EchoTestMessage> =
            self.resolveRef(local, type: EchoTestMessage.self, id: refOnRemoteSystem.id, on: remote)
        remoteRef.tell(EchoTestMessage(string: "test", respondTo: localRef))

        try probe.expectMessage("response:echo:test")
    }

    internal func test_sendingToNonTopLevelRemoteRef_shouldWork() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.serialization.register(EchoTestMessage.self)
            settings.serialization.register(SerializationTestMessage.self)
            settings.serialization.register(EchoTestMessage.self)
        }

        let probe: ActorTestProbe<String> = self.testKit(local).makeTestProbe("X", expecting: String.self)

        let refOnRemoteSystem: ActorRef<EchoTestMessage> = try remote.spawn(
            "remoteAcquaintance",
            .receiveMessage { message in
                message.respondTo.tell("echo:\(message.string)")
                return .same
            }
        )

        local.cluster.join(endpoint: remote.cluster.node.endpoint)

        try assertAssociated(local, withExactly: remote.settings.bindNode)

        let remoteRef: ActorRef<EchoTestMessage> =
            self.resolveRef(local, type: EchoTestMessage.self, id: refOnRemoteSystem.id, on: remote)

        let _: ActorRef<Int> = try local.spawn(
            "localRef",
            .setup { context in
                let child: ActorRef<String> = try context.spawn(
                    .anonymous,
                    .receiveMessage { message in
                        probe.tell("response:\(message)")
                        return .same
                    }
                )

                remoteRef.tell(EchoTestMessage(string: "test", respondTo: child))

                return .receiveMessage { _ in .same }
            }
        )

        try probe.expectMessage("response:echo:test")
    }

    internal func test_sendingToRemoteAdaptedRef_shouldWork() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.serialization.register(EchoTestMessage.self)
            settings.serialization.register(SerializationTestMessage.self)
            settings.serialization.register(EchoTestMessage.self)
        }

        let probe: ActorTestProbe<String> = self.testKit(local).makeTestProbe("X", expecting: String.self)

        let refOnRemoteSystem: ActorRef<EchoTestMessage> = try remote.spawn(
            "remoteAcquaintance",
            .receiveMessage { message in
                message.respondTo.tell("echo:\(message.string)")
                return .same
            }
        )

        local.cluster.join(endpoint: remote.cluster.node.endpoint)

        try assertAssociated(local, withExactly: remote.settings.bindNode)

        let remoteRef: ActorRef<EchoTestMessage> =
            self.resolveRef(local, type: EchoTestMessage.self, id: refOnRemoteSystem.id, on: remote)

        let _: ActorRef<WrappedString> = try local.spawn(
            "localRef",
            .setup { context in
                let adaptedRef: ActorRef<String> =
                    context.messageAdapter(from: String.self) { WrappedString(string: $0) }
                remoteRef.tell(EchoTestMessage(string: "test", respondTo: adaptedRef))
                return .receiveMessage { message in
                    probe.tell("response:\(message.string)")
                    return .same
                }
            }
        )

        try probe.expectMessage("response:echo:test")
    }

    internal func test_actorRefsThatWereSentAcrossMultipleNodeHops_shouldBeAbleToReceiveMessages() async throws {
        let (local, remote): (ClusterSystem, ClusterSystem) = await setUpPair { settings in
            settings.serialization.register(SerializationTestMessage.self)
            settings.serialization.register(EchoTestMessage.self)
        }
        remote.cluster.join(endpoint: local.cluster.node.endpoint)

        try assertAssociated(local, withExactly: remote.cluster.node)

        let thirdSystem: ClusterSystem = await setUpNode("ClusterAssociationTests") { settings in
            settings.bindPort = 9_119
            settings.serialization.register(SerializationTestMessage.self)
            settings.serialization.register(EchoTestMessage.self)
        }

        thirdSystem.cluster.join(endpoint: local.cluster.node.endpoint)
        thirdSystem.cluster.join(endpoint: remote.cluster.node.endpoint)
        try assertAssociated(thirdSystem, withExactly: [local.cluster.node, remote.cluster.node])
        let thirdTestKit: ActorTestKit = self.testKit(thirdSystem)

        let localRef: ActorRef<EchoTestMessage> = try local.spawn(
            "Local",
            .receiveMessage { message in
                message.respondTo.tell("local:\(message.string)")
                return .stop
            }
        )

        let localRefRemote: ActorRef<EchoTestMessage> =
            self.resolveRef(remote, type: EchoTestMessage.self, id: localRef.id, on: local)

        let remoteRef: ActorRef<EchoTestMessage> = try remote.spawn(
            "Remote",
            .receiveMessage { message in
                localRefRemote.tell(EchoTestMessage(string: "remote:\(message.string)", respondTo: message.respondTo))
                return .stop
            }
        )

        let remoteRefThird: ActorRef<EchoTestMessage> =
            self.resolveRef(thirdSystem, type: EchoTestMessage.self, id: remoteRef.id, on: remote)

        let probeThird: ActorTestProbe<String> = thirdTestKit.makeTestProbe(expecting: String.self)

        remoteRefThird.tell(EchoTestMessage(string: "test", respondTo: probeThird.ref))

        try probeThird.expectMessage().shouldEqual("local:remote:test")
    }
}
