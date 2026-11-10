// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

private enum ValidActorPathSymbols {
    static let firstLowercase: UnicodeScalar = "a"
    static let lastLowercase: UnicodeScalar = "z"
    static let firstUppercase: UnicodeScalar = "A"
    static let lastUppercase: UnicodeScalar = "Z"
    static let zero: UnicodeScalar = "0"
    static let nine: UnicodeScalar = "9"

    static let extraSymbols: String.UnicodeScalarView = "-_.*$+:@&=,!~';<>()".unicodeScalars
}

/// Represents a single segment (actor name) of an ActorPath.
public struct ActorPathSegment: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    internal static let userRoot: ActorPathSegment = .init(validated: "user")
    internal static let systemRoot: ActorPathSegment = .init(validated: "system")
    internal static let actorRefReceptionist: ActorPathSegment = .init(validated: "receptionist-ref")
    internal static let distributedActorReceptionist: ActorPathSegment = .init(validated: "receptionist")
    internal static let deadRoot: ActorPathSegment = .init(validated: "dead")
    internal static let deadLetters: ActorPathSegment = .init(validated: "letters")

    /// Name represented by this validated path segment.
    public let value: String

    /// The segment's name.
    public var description: String {
        "\(self.value)"
    }

    /// The segment's name for diagnostic output.
    public var debugDescription: String {
        "\(self.value)"
    }

    /// Validates and creates an actor path segment.
    public init(_ name: String) throws {
        try Self.validatePathSegment(name)
        self.value = name
    }

    // optimize so we don't alloc into the String() here
    internal init(_ name: Substring) throws {
        try self.init(String(name))
    }

    private init(validated name: String) {
        self.value = name
    }

    internal static func validatePathSegment(_ name: String) throws {
        if name.isEmpty {
            throw ActorPathError.illegalActorPathElement(name: name, illegal: "", index: 0)
        }

        // benchmark
        func isValidASCII(_ scalar: Unicode.Scalar) -> Bool {
            (scalar >= ValidActorPathSymbols.firstLowercase && scalar <= ValidActorPathSymbols.lastLowercase)
                || (scalar >= ValidActorPathSymbols.firstUppercase && scalar <= ValidActorPathSymbols.lastUppercase)
                || (scalar >= ValidActorPathSymbols.zero && scalar <= ValidActorPathSymbols.nine)
                || ValidActorPathSymbols.extraSymbols.contains(scalar)
        }

        // accept hex and url encoded things as well
        // http://www.ietf.org/rfc/rfc2396.txt
        var position: Int = 0
        for character in name {
            guard let scalar = character.unicodeScalars.first, scalar.isASCII, isValidASCII(scalar) else {
                throw ActorPathError.illegalActorPathElement(name: name, illegal: "\(character)", index: position)
            }
            position += 1
        }
    }
}
