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

import CDistributedActorsMailbox
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf

extension Serialization.Manifest: CustomStringConvertible {
    public var description: String {
        "Serialization.Manifest(\(serializerID), hint: \(hint ?? "<no-hint>"))"
    }
}

extension Serialization.Manifest: ProtobufRepresentable {
    public typealias ProtobufRepresentation = _ProtoManifest

    // ProtobufRepresentable conformance
    public init(fromProto proto: ProtobufRepresentation, context _: Serialization.Context) {
        self.init(fromProto: proto)
    }

    // Convenience API for decoding manually
    public init(fromProto proto: ProtobufRepresentation) {
        let hint: String? = proto.hint.isEmpty ? nil : proto.hint
        self.serializerID = .init(proto.serializerID)
        self.hint = hint
    }

    // ProtobufRepresentable conformance
    public func toProto(context _: Serialization.Context) -> ProtobufRepresentation {
        self.toProto()
    }

    // Convenience API for encoding manually
    public func toProto() -> ProtobufRepresentation {
        var proto: ProtobufRepresentation = ProtobufRepresentation()
        proto.serializerID = self.serializerID.value
        if let hint = self.hint {
            proto.hint = hint
        }
        return proto
    }
}
