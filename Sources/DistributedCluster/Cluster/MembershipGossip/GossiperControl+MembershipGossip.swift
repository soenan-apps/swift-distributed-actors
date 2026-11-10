// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

internal let kMembershipGossipIdentifier: StringGossipIdentifier = "membership"

extension GossiperControl where Gossip == Cluster.MembershipGossip {
    internal func update(payload: Gossip) {
        self.update(kMembershipGossipIdentifier, payload: payload)
    }

    internal func remove() {
        self.remove(kMembershipGossipIdentifier)
    }

    internal func sideChannelTell(message: Any) {
        self.sideChannelTell(kMembershipGossipIdentifier, message: message)
    }
}
