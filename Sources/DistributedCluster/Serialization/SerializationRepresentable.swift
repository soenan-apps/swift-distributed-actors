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

import Foundation

/// 型が優先するワイヤー形式を指定する。
public protocol SerializationRepresentable {
    /// この型で優先するワイヤー形式ID。
    static var defaultSerializerID: Serialization.SerializerID? { get }
}

extension SerializationRepresentable {
    /// 個別の指定がなければシステム既定の形式を使用する。
    public static var defaultSerializerID: Serialization.SerializerID? {
        nil
    }
}
