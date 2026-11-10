// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Logging

/// Actor内で同じ型のsubReceiveを識別するキー。
public struct SubReceiveId<SubMessage>: Hashable, Equatable,
    ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    /// 空白とVoid表記を正規化した識別子。
    public let id: String

    /// メッセージ型の名前をキーとして使用する。
    public init(_: SubMessage.Type) {
        let typeName: String = String(reflecting: SubMessage.self)
            .replacingOccurrences(of: "()", with: "Void")
            .replacingOccurrences(of: " ", with: "")
        self.id = typeName
    }

    /// 指定した識別子を正規化する。
    public init(id: String, _: SubMessage.Type = SubMessage.self) {
        self.id =
            id
            .replacingOccurrences(of: "()", with: "Void")
            .replacingOccurrences(of: " ", with: "")
    }

    /// 文字列リテラルを識別子として使用する。
    public init(stringLiteral value: String) {
        self.init(id: value)
    }
}
