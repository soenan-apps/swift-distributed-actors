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

import Logging
import NIO

extension Leadership {
    internal final class Shell {
        internal static let naming: ActorNaming = "leadership"

        private var membership: Cluster.Membership
        private var election: LeaderElection

        internal var behavior: Behavior<Cluster.Event> {
            .setup { context in
                context.log.trace("Configured with \(self.election)")
                context.system.cluster.events.subscribe(context.myself)

                _ = self.membership.applyMembershipChange(
                    Cluster.MembershipChange(
                        node: context.system.cluster.node, previousStatus: nil, toStatus: .joining
                    )
                )
                return self.runElection(context)
            }
        }

        private var ready: Behavior<Cluster.Event> {
            .receive { context, event in
                switch event {
                case .snapshot(let membership):
                    self.membership = membership
                    return .same

                case .membershipChange(let change):
                    guard self.membership.applyMembershipChange(change) != nil else {
                        return .same  // nothing changed, no need to select anew
                    }

                    return self.runElection(context)

                case .reachabilityChange(let change):
                    _ = self.membership.applyReachabilityChange(change)

                    return self.runElection(context)

                case .leadershipChange:
                    return .same  // we are the source of such events!

                case .nonExhaustive:
                    context.log.error(
                        "Received Cluster.Event [\(event)]. This should not happen, please file an issue."
                    )
                    return .same
                }
            }
        }

        internal init(_ election: LeaderElection) {
            self.election = election
            self.membership = .empty
        }

        internal func runElection(_ context: ActorContext<Cluster.Event>) -> Behavior<Cluster.Event> {
            var electionContext: LeaderElectionContext = LeaderElectionContext(context)
            electionContext.log[metadataKey: "leadership/election"] = "\(String(reflecting: type(of: self.election)))"
            let electionResult: LeaderElectionResult = self.election.runElection(
                context: electionContext, membership: self.membership
            )

            return context.awaitResult(of: electionResult, timeout: .effectivelyInfinite) { result in
                switch result {
                case .success(.some(let leadershipChange)):
                    guard let changed = try self.membership.applyLeadershipChange(to: leadershipChange.newLeader) else {
                        context.log.trace(
                        """
                        The leadership change that was decided on by \(self.election) results in no change \
                        from current leadership state.
                        """
                    )
                        return self.ready
                    }
                    context.system.cluster.ref.tell(.requestMembershipChange(.leadershipChange(changed)))
                    return self.ready

                case .success(.none):
                    // no change decided upon
                    return self.ready

                case .failure(let err):
                    context.log.warning("Failed to select leader... Error: \(err)")
                    return self.ready
                }
            }
        }
    }
}
