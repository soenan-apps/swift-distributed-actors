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
import MultiNodeTestKit
import NIOCore
import NIOPosix
import OrderedCollections

import struct Foundation.Date
import class Foundation.FileHandle
import struct Foundation.URL

#if canImport(Darwin) || canImport(Glibc)
import class Foundation.Process
#endif

internal enum MultiNode {
    internal struct Endpoint {
        internal let name: String

        internal let sactHost: String
        internal let sactPort: Int

        internal let deployHost: String?
        internal let deployPort: Int?
    }

    internal static func parseAllNodes(_ string: String) -> [Self.Endpoint] {
        var nodes: [Self.Endpoint] = []
        let sNodes: [Substring] = string.split(separator: ",")
        nodes.reserveCapacity(sNodes.count)

        func fail() -> Never {
            fatalError("Bad node list syntax: \(string)")
        }
        for sNode in sNodes {
            guard let atIndex = sNode.firstIndex(of: "@") else {
                fail()
            }
            let name: Substring = sNode[sNode.startIndex..<atIndex]

            guard let colonIndex = sNode.firstIndex(of: ":") else {
                fail()
            }
            let host: Substring = sNode[sNode.index(after: atIndex)..<colonIndex]

            guard let port = Int(sNode[sNode.index(after: colonIndex)..<sNode.endIndex]) else {
                fail()
            }

            let node: Self.Endpoint = Self.Endpoint(
                name: String(name),
                sactHost: String(host),
                sactPort: port,
                deployHost: nil,
                deployPort: nil
            )

            nodes.append(node)
        }
        return nodes
    }

}
