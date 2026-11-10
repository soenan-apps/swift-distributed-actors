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

extension Cluster {
    /// A failed membership transition or an unmet membership observation requirement.
    public struct MembershipError: Error, CustomStringConvertible {
        internal let underlying: MembershipFailureStorage

        public var description: String {
            "\(Self.self)(\(self.underlying.error), at: \(self.underlying.file):\(self.underlying.line))"
        }

        internal init(_ error: MembershipFailureReason, file: String, line: UInt) {
            self.underlying = MembershipFailureStorage(error: error, file: file, line: line)
        }
    }
}
