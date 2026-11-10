import XCTest

@testable import DistributedCluster

private enum RegisteredReferences<Message: Codable> {
    case countOnly
    case exact(Set<ActorRef<Message>>)
}

extension ActorTestKit {
    /// Waits until the receptionist lists the expected number of references.
    @available(*, deprecated, message: "Will be replaced by a DistributedActor-based API. Issue #824")
    public func ensureRegistered<Message>(
        key: Reception.Key<ActorRef<Message>>,
        expectedCount: Int = 1,
        within: Duration = .seconds(3)
    ) throws {
        try self.ensureRegistered(key: key, expectedCount: expectedCount, references: .countOnly, within: within)
    }

    /// Waits until both the reference count and the exact reference set match.
    @available(*, deprecated, message: "Will be replaced by a DistributedActor-based API. Issue #824")
    public func ensureRegistered<Message>(
        key: Reception.Key<ActorRef<Message>>,
        expectedRefs: Set<ActorRef<Message>>,
        expectedCount: Int = 1,
        within: Duration = .seconds(3)
    ) throws {
        try self.ensureRegistered(
            key: key,
            expectedCount: expectedCount,
            references: .exact(expectedRefs),
            within: within
        )
    }

    private func ensureRegistered<Message>(
        key: Reception.Key<ActorRef<Message>>,
        expectedCount: Int,
        references: RegisteredReferences<Message>,
        within: Duration
    ) throws {
        let probe: ActorTestProbe<Reception.Listing<ActorRef<Message>>> = self.makeTestProbe()
        try self.eventually(within: within) {
            self.system.actorRefReceptionist.lookup(key, replyTo: probe.ref, timeout: .effectivelyInfinite)
            let listing: Reception.Listing<ActorRef<Message>> = try probe.expectMessage()
            guard listing.refs.count == expectedCount else {
                throw self.error(
                    "Expected Reception.Listing for key [\(key)] to have count [\(expectedCount)], "
                        + "but got [\(listing.refs.count)]"
                )
            }
            if case .exact(let expectedRefs) = references, Set(listing.refs) != expectedRefs {
                throw self.error(
                    "Expected Reception.Listing for key [\(key)] to have refs \(expectedRefs), "
                        + "but got \(listing.refs)"
                )
            }
        }
    }
}
