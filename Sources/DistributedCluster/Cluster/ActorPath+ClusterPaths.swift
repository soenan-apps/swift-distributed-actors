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

extension ActorPath {
    internal static let clusterShellPath: ActorPath =
        // swiftlint:disable:next force_try
        try! ActorPath.systemRoot.appendingKnownUnique(ClusterShell.naming)

    internal static let clusterGossipPath: ActorPath =
        // swiftlint:disable:next force_try
        try! ActorPath.clusterShellPath.appending("gossip")
}
