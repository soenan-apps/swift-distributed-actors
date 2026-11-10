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
import OrderedCollections

/// A finite set of named nodes used by a multi-node suite.
public protocol MultiNodeNodes: Hashable, CaseIterable {
    /// Stable node name used in endpoint lookup.
    var rawValue: String { get }
}
