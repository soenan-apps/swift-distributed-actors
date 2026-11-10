// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedCluster
import Logging

extension MultiNode {
    public struct Checkpoint: Codable, Hashable, CustomStringConvertible {
        internal let name: String

        internal let file: String
        internal let line: UInt

        public var description: String {
            "\(Self.self)(\(self.name) at \(self.file):\(self.line))"
        }

        public init(name: String, file: String = #fileID, line: UInt = #line) {
            self.name = name
            self.file = file
            self.line = line
        }

    }
}
