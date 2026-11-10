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

internal enum MembershipFailureReason: CustomPrettyStringConvertible {
    case atLeastStatusRequirementNotMet(expectedAtLeast: Cluster.MemberStatus, found: Cluster.Member)
    case awaitStatusTimedOut(Duration, Error?)
    case nonMemberLeaderSelected(Cluster.Membership, wannabeLeader: Cluster.Member)
    case notFound(Cluster.Node, membership: Cluster.Membership)
    case notFoundAny(Cluster.Endpoint, membership: Cluster.Membership)
    case statusRequirementNotMet(expected: Cluster.MemberStatus, found: Cluster.Member)

    internal var prettyDescription: String {
        "\(self), details: \(self.details)"
    }

    private var details: String {
        switch self {
        case let .nonMemberLeaderSelected(membership, wannabeLeader):
            return "[\(wannabeLeader)] selected leader but is not a member [\(membership)]"

        case let .notFound(node, membership):
            return "[\(node)] is not a member [\(membership)]"

        case let .notFoundAny(node, membership):
            return "[\(node)] is not a member [\(membership)]"

        case let .atLeastStatusRequirementNotMet(expectedAtLeastStatus, foundMember):
            return """
            Expected \(reflecting: foundMember.node) to be seen as at-least \
            [\(expectedAtLeastStatus)] but was [\(foundMember.status)]
            """

        case let .statusRequirementNotMet(expectedStatus, foundMember):
            return """
            Expected \(reflecting: foundMember.node) to be seen as \
            [\(expectedStatus)] but was [\(foundMember.status)]
            """

        case let .awaitStatusTimedOut(duration, lastError):
            let lastErrorMessage: String
            if let error = lastError {
                lastErrorMessage = "Last error: \(error)"
            } else {
                lastErrorMessage = "Last error: <none>"
            }

            return "No result within \(duration.prettyDescription). \(lastErrorMessage)"
        }
    }
}
