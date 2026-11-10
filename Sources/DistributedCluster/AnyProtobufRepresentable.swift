// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2020 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

/// Marker for values encoded through a Protocol Buffers representation.
public protocol AnyProtobufRepresentable: Codable, SerializationRepresentable {}

extension AnyProtobufRepresentable {
    /// Selects the Protocol Buffers serializer for conforming values.
    public static var defaultSerializerID: Serialization.SerializerID? {
        .protobufRepresentable
    }
}
