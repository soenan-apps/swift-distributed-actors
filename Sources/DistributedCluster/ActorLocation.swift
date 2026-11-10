// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

@usableFromInline
internal enum ActorLocation: Hashable, Sendable {
    case local(Cluster.Node)
    case remote(Cluster.Node)
}
