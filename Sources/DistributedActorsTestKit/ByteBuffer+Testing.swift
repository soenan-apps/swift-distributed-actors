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

import DistributedActorsConcurrencyHelpers
import Foundation
import NIO
import NIOFoundationCompat
import XCTest

@testable import DistributedCluster

extension Serialization.Buffer {
    /// Decodes UTF-8 for visual inspection, describing undecodable data instead.
    public func stringDebugDescription() -> String {
        switch self {
        case .data(let data):
            return data.stringDebugDescription()

        case .nioByteBuffer(let buffer):
            return buffer.stringDebugDescription()

        case .nonExhaustive:
            return "\(self)"
        }
    }
}

extension Data {
    /// Decodes UTF-8 for visual inspection, describing undecodable data instead.
    public func stringDebugDescription() -> String {
        if let string = String(data: self, encoding: .utf8) {
            return string
        }
        return "<<NOT UTF8 ENCODED: \(self)>>"
    }
}

extension ByteBuffer {
    /// Reads UTF-8 from offset zero, trapping when those bytes are not readable UTF-8.
    public func stringDebugDescription() -> String {
        guard let string = self.getString(at: 0, length: self.readableBytes) else {
            preconditionFailure("Buffer does not contain readable UTF-8 at offset zero")
        }
        return string
    }
}
