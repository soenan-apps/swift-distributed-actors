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

import struct Foundation.Data
import NIO
import protocol Swift.Decoder  // to prevent shadowing by the ones in SwiftProtobuf
import protocol Swift.Encoder  // to prevent shadowing by the ones in SwiftProtobuf
import SwiftProtobuf

/// Protobuf serializer for internal protobuf messages only.
internal final class InternalProtobufSerializer<T: InternalProtobufRepresentable>:
    BaseProtobufSerializer<T, T.ProtobufRepresentation> {
    override internal func toProto(_ message: T, context _: Serialization.Context) throws -> T.ProtobufRepresentation {
        try message.toProto(context: self.serializationContext)
    }

    override internal func fromProto(_ proto: T.ProtobufRepresentation, context _: Serialization.Context) throws -> T {
        try T(fromProto: proto, context: self.serializationContext)
    }
}
