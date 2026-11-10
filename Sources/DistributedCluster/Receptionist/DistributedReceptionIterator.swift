import Distributed
import Logging

/// Emits discovered actors from one receptionist subscription.
public final class DistributedReceptionIterator<Guest: DistributedActor>: AsyncIteratorProtocol
where Guest.ActorSystem == ClusterSystem {
    public typealias Element = Guest

    internal var underlying: AsyncStream<Guest>.Iterator

    internal init(
        receptionist __secretlyKnownToBeLocal: OpLogDistributedReceptionist,
        key: DistributedReception.Key<Guest>,
        file: String,
        line: UInt
    ) {
        let pair: (stream: AsyncStream<Guest>, continuation: AsyncStream<Guest>.Continuation) =
            AsyncStream.makeStream(of: Guest.self)
        self.underlying = pair.stream.makeAsyncIterator()
        let continuation: AsyncStream<Guest>.Continuation = pair.continuation
        let system: ClusterSystem = __secretlyKnownToBeLocal.actorSystem
        let subscription: DistributedListingSubscription = DistributedListingSubscription(
            subscriptionID: ObjectIdentifier(self),
            file: file,
            line: line,
            key: key.asAnyKey
        ) { [weak system] guestID in
            guard let system else {
                continuation.finish()
                return
            }
            guard let guest = try? Guest.resolve(id: guestID, using: system) else {
                system.log.warning("Failed to resolve \(guestID) for listing \(self)")
                return
            }
            switch continuation.yield(guest) {
            case .terminated, .dropped:
                continuation.finish()

            case .enqueued:
                break

            @unknown default:
                assertionFailure("Unexpected case!")
            }
        }
        Task {
            await __secretlyKnownToBeLocal.addSubscription(subscription: subscription, file: file, line: line)
        }
        continuation.onTermination = { @Sendable _ in
            Task {
                await __secretlyKnownToBeLocal.cancelSubscription(subscription: subscription)
            }
        }
    }

    public func next() async -> Guest? {
        await self.underlying.next()
    }
}
