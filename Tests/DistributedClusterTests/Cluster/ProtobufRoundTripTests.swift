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

import DistributedActorsTestKit
import Foundation
import NIO
import SwiftProtobuf
import XCTest

@testable import DistributedCluster

internal final class ProtobufRoundTripTests: SingleClusterSystemXCTestCase {
    internal let allocator: ByteBufferAllocator = ByteBufferAllocator()
    internal var node: Cluster.Node {
        self.system.cluster.node
    }

    internal var localActorAddress: ActorID {
        get throws {
            try ActorPath.userRoot.appending("hello")
                .makeLocalID(on: self.system.cluster.node, incarnation: .wellKnown)
        }
    }

    internal func check<Value: ProtobufRepresentable & Equatable>(_ value: Value) throws {
        let context: Serialization.Context = Serialization.Context(
            log: self.system.log,
            system: self.system,
            allocator: self.system.serialization.allocator
        )
        let proto: Value.ProtobufRepresentation = try value.toProto(context: context)
        let back: Value = try Value(fromProto: proto, context: context)
        back.shouldEqual(value)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Core actor types

    internal func test_roundTrip_ActorID() throws {
        try self.check(self.localActorAddress)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Handshake protocol

    internal func test_roundTrip_Wire_HandshakeOffer() throws {
        let offer: Wire.HandshakeOffer = Wire.HandshakeOffer(
            version: .init(reserved: 2, major: 3, minor: 5, patch: 5),
            originNode: self.node,
            targetEndpoint: self.node.endpoint
        )
        let proto: _ProtoHandshakeOffer = _ProtoHandshakeOffer(offer)
        let back: Wire.HandshakeOffer = try Wire.HandshakeOffer(fromProto: proto)
        back.shouldEqual(offer)
    }
}
