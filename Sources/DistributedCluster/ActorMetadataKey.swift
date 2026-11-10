// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

/// 値の型に依存しないmetadataキーのマーカー。
public protocol AnyActorMetadataKey {}

/// ActorIDに付随するmetadataのキーと値の型を結び付ける。
public struct ActorMetadataKey<Value: Codable & Sendable>: Hashable, ExpressibleByStringLiteral {
    /// 保存と配送に使用するキー。
    public let id: String

    /// 指定したキーを使用する。
    public init(id: String) {
        self.id = id
    }

    /// 文字列リテラルをキーとして使用する。
    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}
