import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

extension WorkerPoolTests {
    internal func waitForPoolSize(_ pool: WorkerPool<WorkerPoolGreeter>, expected: Int) async throws {
        try await self.testKit.eventually(within: .seconds(3)) {
            let actual: Int = try await pool.size
            guard actual == expected else {
                throw TestError("Expected \(expected) workers, found \(actual)")
            }
        }
    }

    internal func assertSurvivingWorkersReceive(
        _ pool: WorkerPool<WorkerPoolGreeter>,
        workerIDs: [ActorID],
        probes: [ActorID: ActorTestProbe<String>]
    ) async throws {
        for indexForTest in 0...2 {
            _ = try await pool.submit(work: "after-A-dead-\(indexForTest)")

            // A termination can reset the round-robin position, so only check that one survivor receives the item.
            let received: [String] = try workerIDs.compactMap { workerID in
                let probe: ActorTestProbe<String> = try XCTUnwrap(probes[workerID])
                return probe.maybeExpectMessage(within: .milliseconds(200))
            }
            received.count.shouldEqual(1)
            try XCTUnwrap(received.first).shouldStartWith(prefix: "work:after-A-dead-\(indexForTest) at")
        }
    }

    internal func assertRoundRobin(
        _ pool: WorkerPool<WorkerPoolGreeter>,
        ids: [ActorID],
        probes: [ActorID: ActorTestProbe<String>],
        prefix: String,
        indices: ClosedRange<Int>
    ) async throws {
        for index in indices {
            let work: String = "\(prefix)\(index)"
            _ = try await pool.submit(work: work)
            let workerID: ActorID = ids[index % ids.count]
            let probe: ActorTestProbe<String> = try XCTUnwrap(probes[workerID])
            try probe.expectMessage("work:\(work) at \(workerID)")
        }
    }

    internal func assertStaticPoolExhausted(_ pool: WorkerPool<WorkerPoolGreeter>) async throws {
        let error: any Error = try await shouldThrow {
            _ = try await pool.submit(work: "after-all-dead")
        }
        guard let workerPoolError = error as? WorkerPoolError,
            case .staticPoolExhausted(let errorMessage) = workerPoolError.underlying.error
        else {
            throw testKit.fail("Expected WorkerPoolError.staticPoolExhausted, got \(error)")
        }
        errorMessage.shouldContain("Static worker pool exhausted, all workers have terminated")
    }
}
