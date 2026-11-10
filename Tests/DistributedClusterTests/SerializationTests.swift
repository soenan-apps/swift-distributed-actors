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
//

import DistributedActorsTestKit
import Foundation
import NIO
import NIOFoundationCompat
import XCTest

@testable import DistributedCluster

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Example types for serialization tests

internal struct HasStringRef: Codable, Equatable {
    internal let containedRef: ActorRef<String>
}

internal struct HasIntRef: Codable, Equatable {
    internal let containedRef: ActorRef<Int>
}

internal struct InterestingMessage: Codable, Equatable {}

internal struct HasInterestingMessageRef: Codable, Equatable {
    internal let containedInterestingRef: ActorRef<InterestingMessage>
}

/// This is quite an UNUSUAL case, as `ReceivesSystemMessages` is internal, and thus, no user code shall ever send it
/// verbatim like this. We may however, need to send them for some reason internally, and it might be nice to use
/// Codable if we do.
///
/// Since the type is internal, the automatic derivation does not function, and some manual work is needed, which is
/// fine,
/// as we do not expect this case to happen often (or at all), however if the need were to arise, the
/// ReceivesSystemMessagesDecoder
/// enables us to handle this rather easily.
internal struct HasReceivesSystemMsgs: Codable {
    internal let sysRef: ReceivesSystemMessages

    internal init(sysRef: ReceivesSystemMessages) {
        self.sysRef = sysRef
    }

    internal init(from decoder: Decoder) throws {
        self.sysRef = try ReceivesSystemMessagesDecoder.decode(from: decoder)
    }

    internal func encode(to encoder: Encoder) throws {
        try self.sysRef.encode(to: encoder)
    }
}

internal struct NotCodableHasInt: Equatable {
    internal let containedInt: Int
}

internal struct NotCodableHasIntRef: Equatable {
    internal let containedRef: ActorRef<Int>
}

internal struct NotSerializable {
    internal let pos: String

    internal init(_ pos: String) {
        self.pos = pos
    }
}

internal enum NotCodableTestingError: Error, Equatable {
    case errorOne
    case errorTwo
}

internal enum CodableTestingError: String, Error, Equatable, Codable {
    case errorA = "errorA"
    case errorB = "errorB"
}

internal struct PListBinCodableTest: Codable, Equatable {
    internal let name: String
    internal let items: [String]
}

internal struct PListXMLCodableTest: Codable, Equatable {
    internal let name: String
    internal let items: [String]
}

internal class SerializationTests: SingleClusterSystemXCTestCase {
    override internal func setUp() async {
        _ = await self.setUpNode(String(describing: type(of: self))) { settings in
            settings.serialization.register(HasReceivesSystemMsgs.self)
            settings.serialization.register(HasStringRef.self)
            settings.serialization.register(HasIntRef.self)
            settings.serialization.register(HasInterestingMessageRef.self)
            settings.serialization.register(CodableTestingError.self)

            settings.serialization.register(PListBinCodableTest.self, serializerID: .foundationPropertyListBinary)
            settings.serialization.register(PListXMLCodableTest.self, serializerID: .foundationPropertyListXML)
        }
    }

    internal func test_soundness_roundTripBetweenFoundationDataAndNioByteBuffer() throws {
        let allocator: ByteBufferAllocator = ByteBufferAllocator()
        var buf: ByteBuffer = allocator.buffer(capacity: 5)
        buf.writeString("hello")

        let data: Data = try XCTUnwrap(buf.getData(at: 0, length: buf.readableBytes))

        let out: ByteBuffer = data.withUnsafeBytes { bytes in
            var out: ByteBuffer = allocator.buffer(capacity: data.count)
            out.writeBytes(bytes)
            return out
        }

        buf.shouldEqual(out)
    }

    internal func test_serialize_Int_withData() throws {
        let value: Int = 6

        let serialized: Serialization.Serialized = try system.serialization.serialize(value)
        // Deserialize from `Data`
        let deserialized: Int = try system.serialization.deserialize(
            as: Int.self,
            from: .data(
                serialized.buffer.readData()
            ),
            using: serialized.manifest
        )

        deserialized.shouldEqual(value)
    }

}
