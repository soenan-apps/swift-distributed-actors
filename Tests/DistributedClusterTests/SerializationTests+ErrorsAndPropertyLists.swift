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

extension SerializationTests {
    internal func test_serialize_errorEnvelope_stringDescription() throws {
        let description: String = "BOOM!!!"
        let errorEnvelope: ErrorEnvelope = ErrorEnvelope(description: description)

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(errorEnvelope)
        }

        let back: ErrorEnvelope = try shouldNotThrow {
            try system.serialization.deserialize(as: ErrorEnvelope.self, from: serialized)
        }

        guard let bestEffortStringError = back.error as? BestEffortStringError else {
            throw self.testKit.error("\(back.error) is not BestEffortStringError")
        }

        bestEffortStringError.representation.shouldEqual(description)
    }

    internal func test_serialize_errorEnvelope_notCodableError() throws {
        let notCodableError: NotCodableTestingError = .errorTwo
        let errorEnvelope: ErrorEnvelope = ErrorEnvelope(notCodableError)

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(errorEnvelope)
        }

        let back: ErrorEnvelope = try shouldNotThrow {
            try system.serialization.deserialize(as: ErrorEnvelope.self, from: serialized)
        }

        guard let bestEffortStringError = back.error as? BestEffortStringError else {
            throw self.testKit.error("\(back.error) is not BestEffortStringError")
        }

        bestEffortStringError.representation.shouldContain(String(reflecting: NotCodableTestingError.self))
    }

    internal func test_serialize_errorEnvelope_codableError() throws {
        let codableError: CodableTestingError = .errorB
        let errorEnvelope: ErrorEnvelope = ErrorEnvelope(codableError)

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(errorEnvelope)
        }

        let back: ErrorEnvelope = try shouldNotThrow {
            try system.serialization.deserialize(as: ErrorEnvelope.self, from: serialized)
        }

        guard let codableTestingError = back.error as? CodableTestingError else {
            throw self.testKit.error("\(back.error) is not CodableTestingError")
        }

        codableTestingError.shouldEqual(codableError)
    }

    // ====
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: PList coding

    internal func test_plist_binary() throws {
        let test: PListBinCodableTest = PListBinCodableTest(
            name: "foo",
            items: [
                "bar", "baz", "baz", "baz", "baz", "baz", "baz", "baz", "baz", "baz", "baz", "baz", "baz", "baz", "baz",
                "baz",
            ]
        )

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(test)
        }

        let back: PListBinCodableTest = try system.serialization.deserialize(
            as: PListBinCodableTest.self,
            from: serialized
        )

        back.shouldEqual(test)
    }

    internal func test_plist_xml() throws {
        let test: PListXMLCodableTest = PListXMLCodableTest(name: "foo", items: ["bar", "baz"])

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(test)
        }

        let back: PListXMLCodableTest = try system.serialization.deserialize(
            as: PListXMLCodableTest.self,
            from: serialized
        )

        back.shouldEqual(test)
    }

    internal func test_plist_throws_whenWrongFormat() async throws {
        let test: PListXMLCodableTest = PListXMLCodableTest(name: "foo", items: ["bar", "baz"])

        let serialized: Serialization.Serialized = try shouldNotThrow {
            try system.serialization.serialize(test)
        }

        let system2: ClusterSystem = await self.setUpNode("OtherSystem") { settings in
            settings.serialization.register(
                PListXMLCodableTest.self,
                serializerID: .foundationPropertyListBinary
            )  // on purpose "wrong" format
        }

        _ = try shouldThrow {
            _ = try system2.serialization.deserialize(as: PListXMLCodableTest.self, from: serialized)
        }

        let back: PListXMLCodableTest = try system.serialization.deserialize(
            as: PListXMLCodableTest.self,
            from: serialized
        )
        back.shouldEqual(test)
    }
}
