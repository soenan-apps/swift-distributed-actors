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

public struct ClusterInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = any Codable & SendableMetatype

    internal var arguments: [Data] = []
    internal var genericSubstitutions: [String] = []
    internal var throwing: Bool = false

    internal let system: ClusterSystem

    internal init(system: ClusterSystem) {
        self.system = system
    }

    internal init(system: ClusterSystem, arguments: [Data]) {
        self.system = system
        self.arguments = arguments
        self.throwing = false
    }

    public mutating func recordGenericSubstitution<T>(_ type: T.Type) {
        let typeName: String = _mangledTypeName(type) ?? _typeName(type)
        self.genericSubstitutions.append(typeName)
    }

    public mutating func recordArgument<Value: Codable & SendableMetatype>(
        _ argument: RemoteCallArgument<Value>
    ) throws {
        let serialized: Serialization.Serialized = try self.system.serialization.serialize(argument.value)
        let data: Data = serialized.buffer.readData()
        self.arguments.append(data)
    }

    public mutating func recordReturnType<Success: Codable & SendableMetatype>(_: Success.Type) throws {
        // The return type is carried by the distributed method signature.
    }

    public mutating func recordErrorType<E: Error>(_: E.Type) {
        self.throwing = true
    }

    public mutating func doneRecording() {
        // noop
    }
}
