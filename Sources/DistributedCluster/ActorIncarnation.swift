// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

/// 同じActorPathで再作成されたActorを区別する世代番号。
/// 旧Actor宛てのメッセージを、新しいActorへ誤配送しないためにIDへ含める。
public struct ActorIncarnation: Equatable, Hashable, ExpressibleByIntegerLiteral, Sendable, Comparable {
    /// Fixed incarnation reserved for well-known system actors.
    internal static let wellKnown: ActorIncarnation = .init(0)

    internal let value: UInt32

    /// Creates an incarnation from an integer representable by `UInt32`.
    public init(_ value: Int) {
        self.init(UInt32(value))
    }

    /// Creates an incarnation from its unsigned wire value.
    public init(_ value: UInt32) {
        self.value = value
    }

    /// Creates an incarnation from an integer literal.
    public init(integerLiteral value: IntegerLiteralType) {
        self.init(UInt32(value))
    }

    internal init?(_ value: String?) {
        guard let text = value, let number = Int(text), number >= 0 else {
            return nil
        }
        self.init(number)
    }

    /// Creates a random, nonzero incarnation.
    public static func random() -> Self {
        Self(UInt32.random(in: UInt32(1)...UInt32.max))
    }

    /// Orders incarnations by their unsigned wire values.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }
}
