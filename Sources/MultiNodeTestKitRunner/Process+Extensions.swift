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

import ArgumentParser
import DistributedCluster
import NIOCore
import NIOPosix

import class Foundation.FileHandle
import struct Foundation.URL

#if canImport(Darwin) || canImport(Glibc)
import class Foundation.Process
#endif

#if canImport(Darwin) || canImport(Glibc)
// Compatible with Swift on all macOS versions as well as Linux
extension Process {
    internal var binaryPath: String? {
        get {
            if #available(macOS 10.13, *) {  // '*' covers Linux
                return self.executableURL?.path
            } else {
                return self.launchPath
            }
        }
        set {
            if #available(macOS 10.13, *) {  // '*' covers Linux
                self.executableURL = newValue.map { URL(fileURLWithPath: $0) }
            } else {
                self.launchPath = newValue
            }
        }
    }

    internal func runProcess() throws {
        if #available(macOS 10.13, *) {
            try self.run()
        } else {
            self.launch()
        }
    }
}
#endif
