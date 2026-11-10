// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import CDistributedActorsMailbox
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf

internal struct BoxedAnySerializer: AnySerializer, CustomStringConvertible {
    private let serializer: AnySerializer

    internal var description: String {
        "AnySerializer(\(self.serializer))"
    }

    internal init<Serializer: AnySerializer>(_ serializer: Serializer) {
        self.serializer = serializer
    }

    internal func setSerializationContext(_ context: Serialization.Context) {
        self.serializer.setSerializationContext(context)
    }

    internal func setUserInfo<Value>(key: CodingUserInfoKey, value: Value?) {
        self.serializer.setUserInfo(key: key, value: value)
    }

    internal func trySerialize(_ message: Any) throws -> Serialization.Buffer {
        try self.serializer.trySerialize(message)
    }

    internal func tryDeserialize(_ bytes: Serialization.Buffer) throws -> Any {
        try self.serializer.tryDeserialize(bytes)
    }
}
