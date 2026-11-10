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

#if !canImport(Musl)
import Distributed
import Logging
import OrderedCollections

/// A worker-pool configuration or exhaustion failure together with its source location.
public struct WorkerPoolError: Error, CustomStringConvertible {
    internal enum Reason {
        // --- runtime errors
        case staticPoolExhausted(String)

        // --- configuration errors
        case emptyStaticWorkerPool(String)
        case awaitNewWorkersForStaticPool(String)
    }

    internal class Storage {
        internal let error: Reason
        internal let file: String
        internal let line: UInt

        internal init(error: Reason, file: String, line: UInt) {
            self.error = error
            self.file = file
            self.line = line
        }
    }

    internal let underlying: Storage

    public var description: String {
        "\(Self.self)(\(self.underlying.error), at: \(self.underlying.file):\(self.underlying.line))"
    }

    internal init(_ error: Reason, file: String = #fileID, line: UInt = #line) {
        self.underlying = Storage(error: error, file: file, line: line)
    }
}
#endif
