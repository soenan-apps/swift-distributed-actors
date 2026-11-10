// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

/// 分散呼出のエラーを具体的なCodable型のまま返す範囲を設定する。
public struct CodableErrorAllowanceSettings {
    internal enum CodableErrorAllowance {
        case all
        case custom(Set<ObjectIdentifier>)
        case genericOnly
    }

    /// すべてのCodableエラーを元の型のまま返す。
    public static let all: Self = .init(allowance: .all)

    /// すべてのCodableエラーを`GenericRemoteCallError`へ変換する。
    public static let genericOnly: Self = .init(allowance: .genericOnly)

    internal let underlying: CodableErrorAllowance

    internal init(allowance: CodableErrorAllowance) {
        self.underlying = allowance
    }

    /// 指定された型のエラーだけを元の型で返し、ほかは`GenericRemoteCallError`へ変換する。
    public static func custom(allowedTypes: [(Error & Codable).Type]) -> Self {
        let identifiers: Set<ObjectIdentifier> = Set(allowedTypes.lazy.map { ObjectIdentifier($0) })

        return .init(allowance: .custom(identifiers))
    }
}
