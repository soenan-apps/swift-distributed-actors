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

import SWIM

extension Serialization.SerializerID {

    // ~~~~~~~~~~~~~~~~ general purpose serializer ids ~~~~~~~~~~~~~~~~
    /// 転送を許可しないメッセージのID。
    public static let doNotSerialize: Self = 0

    /// 型ヒントで専用シリアライザーを選ぶID。
    public static let specializedWithTypeHint: Self = 1
    /// Protobuf 表現を使うワイヤー形式ID。
    public static let protobufRepresentable: Self = 2

    /// Foundation JSON のワイヤー形式ID。
    public static let foundationJSON: Self = 3
    /// バイナリ property-list のワイヤー形式ID。
    public static let foundationPropertyListBinary: Self = 4
    /// XML property-list のワイヤー形式ID。
    public static let foundationPropertyListXML: Self = 5
    // ... reserved = 6
    // ... -- || --
    // ... reserved = 16

    /// Helper function to never accidentally register a not-AnyProtobufRepresentable as such.
    public static func checkProtobufRepresentable<M: AnyProtobufRepresentable>(_: M.Type) -> Self {
        .protobufRepresentable
    }

    // ~~~~~~~~~~~~~~~~ users may use ids above 16 ~~~~~~~~~~~~~~~~
    // reserved for end-users
}
