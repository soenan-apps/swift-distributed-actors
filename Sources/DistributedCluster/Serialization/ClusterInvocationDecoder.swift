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

import Distributed
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf

public struct ClusterInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = any Codable & SendableMetatype

    internal enum State {
        // Interceptors may invoke a local target directly.
        case localProxyCall(ClusterSystem.InvocationEncoder)
        case remoteCall(message: InvocationMessage)
    }

    internal let system: ClusterSystem
    internal let state: State
    internal var argumentIdx: Int = 0

    public init(system: ClusterSystem, message: InvocationMessage) {
        self.system = system
        self.state = .remoteCall(message: message)
    }

    internal init(system: ClusterSystem, invocation: ClusterSystem.InvocationEncoder) {
        self.system = system
        self.state = .localProxyCall(invocation)
    }

    public mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
        let genericSubstitutions: [String]
        switch self.state {
        case .remoteCall(let message):
            genericSubstitutions = message.genericSubstitutions

        case .localProxyCall(let invocation):
            genericSubstitutions = invocation.genericSubstitutions
        }

        return try genericSubstitutions.map { typeName in
            guard let type = _typeByName(typeName) else {
                throw SerializationError(.notAbleToDeserialize(hint: typeName))
            }
            return type
        }
    }

    public mutating func decodeNextArgument<Argument: Codable & SendableMetatype>() throws -> Argument {
        let argumentData: Data

        switch self.state {
        case .remoteCall(let message):
            guard self.argumentIdx < message.arguments.count else {
                throw SerializationError(
                    .notEnoughArgumentsEncoded(expected: self.argumentIdx + 1, have: message.arguments.count)
                )
            }

            argumentData = message.arguments[self.argumentIdx]
            self.argumentIdx += 1

            let manifest: Serialization.Manifest = try system.serialization.outboundManifest(Argument.self)

            let serialized: Serialization.Serialized = Serialization.Serialized(
                manifest: manifest,
                buffer: Serialization.Buffer.data(argumentData)
            )
            return try system.serialization.deserialize(as: Argument.self, from: serialized)

        case .localProxyCall(let invocation):
            guard self.argumentIdx < invocation.arguments.count else {
                throw SerializationError(
                    .notEnoughArgumentsEncoded(expected: self.argumentIdx + 1, have: invocation.arguments.count)
                )
            }

            argumentData = invocation.arguments[self.argumentIdx]
            self.argumentIdx += 1
        }

        let manifest: Serialization.Manifest = try self.system.serialization.outboundManifest(Argument.self)

        let serialized: Serialization.Serialized = Serialization.Serialized(
            manifest: manifest,
            buffer: Serialization.Buffer.data(argumentData)
        )
        return try self.system.serialization.deserialize(as: Argument.self, from: serialized)
    }

    public mutating func decodeErrorType() -> Any.Type? {
        nil
    }

    public mutating func decodeReturnType() -> Any.Type? {
        nil
    }
}
