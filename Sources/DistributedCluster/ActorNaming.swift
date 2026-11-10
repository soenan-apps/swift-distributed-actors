// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import DistributedActorsConcurrencyHelpers

/// 名前の生成に使用する、コンテキスト内の連番。
internal struct ActorNamingContext {
    private var sequenceNumber: UInt32

    internal init() {
        self.sequenceNumber = 0
    }

    internal mutating func nextSequenceNr() -> UInt32 {
        defer { self.sequenceNumber += 1 }
        return self.sequenceNumber
    }
}

/// Actorを作成する際の、名前または名前の生成規則。
public struct ActorNaming: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Hashable {
    internal enum Naming: Hashable {
        case prefixed(prefix: String, suffixScheme: SuffixScheme)
        case unique(String)
    }

    internal enum SuffixScheme {
        /// 人が区別しやすいz-base-32の文字列。辞書順は生成順を表さない。
        case letters
        /// 生成順に増加する数値。
        case sequentialNumeric
    }

    private static let alphabet: [UnicodeScalar] = [
        "y", "b", "n", "d", "r", "f", "g", "8",
        "e", "j", "k", "m", "c", "p", "q", "x",
        "o", "t", "1", "u", "w", "i", "s", "z",
        "a", "3", "4", "5", "h", "7", "6", "9",
    ]
    // The fixed 32-symbol alphabet uses the low five bits for each digit.
    private static let alphabetIndexMask: UInt32 = 0b1_1111

    /// 問い合わせ用Actorの名前を生成する。
    internal static var ask: ActorNaming = .init(unchecked: .prefixed(prefix: "$ask", suffixScheme: .letters))

    /// messageAdapterに使用する固定名。
    internal static let adapter: ActorNaming = .init(unchecked: .unique("$messageAdapter"))

    /// 匿名Actorに使用する名前の生成規則。
    public static var anonymous: Self {
        .init(unchecked: .prefixed(prefix: "$anonymous", suffixScheme: .letters))
    }

    internal let naming: Naming

    /// システム内部で使用する、検証済みまたは予約済みの名前。
    internal init(unchecked: Naming) {
        self.naming = unchecked
    }

    /// 文字列を一意な名前として使用する。
    public init(stringLiteral value: String) {
        self = .unique(value)
    }

    /// 同じ親の下で一意な名前。先頭の$はシステム用に予約する。
    public static func unique(_ name: String) -> Self {
        Self.validateUserProvided(nameOrPrefix: name)
        return .init(unchecked: .unique(name))
    }

    /// 指定したprefixに、コンテキスト内の連番をz-base-32で付加する。
    public static func prefixed(with prefix: String) -> Self {
        Self.validateUserProvided(nameOrPrefix: prefix)
        return .init(unchecked: .prefixed(prefix: prefix, suffixScheme: .letters))
    }

    private static func validateUserProvided(nameOrPrefix: String) {
        guard !nameOrPrefix.starts(with: "$") else {
            fatalError("User defined actor names MUST NOT start with $ sign, yet was: [\(nameOrPrefix)]")
        }
    }

    internal func makeName(_ context: inout ActorNamingContext) -> String {
        switch self.naming {
        case let .unique(name):
            return name

        case let .prefixed(prefix, scheme):
            var resultingName: String = "\(prefix)-"
            switch scheme {
            case .sequentialNumeric:
                let sequenceNumber: UInt32 = context.nextSequenceNr()
                resultingName.append("\(sequenceNumber)")

            case .letters:
                let sequenceNumber: UInt32 = context.nextSequenceNr()
                var next: UInt32 = sequenceNumber
                repeat {
                    let scalar: UnicodeScalar = Self.alphabet[Int(next & Self.alphabetIndexMask)]
                    resultingName.unicodeScalars.append(scalar)
                    next &>>= 5
                } while next > 0
            }
            return resultingName
        }
    }
}
