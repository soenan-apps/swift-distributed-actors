// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

extension ActorID: Hashable {
    public static func == (lhs: ActorID, rhs: ActorID) -> Bool {
        // Check the metadata based well-known identity names.
        //
        // The legacy "well known path" is checked using the normal path below,
        // since it is implemented as incarnation == 0, and an unique path.
        if let lhsWellKnownName = lhs.metadata.wellKnown {
            if let rhsWellKnownName = rhs.metadata.wellKnown {
                // If we're comparing "well known" actors, we ignore the concrete incarnation,
                // and compare the well known name instead. This works for example for "$receptionist"
                // and other well known names, that can be resolved using them, without an incarnation number.
                if lhsWellKnownName == rhsWellKnownName, lhs.node == rhs.node {
                    return true
                }
            } else {
                // 'lhs' WAS well known, but 'rhs' was not
                return false
            }
        } else if rhs.metadata.wellKnown != nil {
            // 'lhs' was NOT well known, but 'rhs' was:
            return false
        }

        // quickest to check if the incarnations are the same
        // if they happen to be equal, we don't know yet for sure if it's the same actor or not,
        // as incarnation is just a random ID thus we need to compare the node and path as well
        return lhs.incarnation == rhs.incarnation && lhs.node == rhs.node && lhs.path == rhs.path
    }

    public func hash(into hasher: inout Hasher) {
        if let wellKnownName = self.metadata.wellKnown {
            hasher.combine(wellKnownName)
        } else {
            hasher.combine(self.incarnation)
        }
        hasher.combine(self.node)
        hasher.combine(self.path)
    }
}
