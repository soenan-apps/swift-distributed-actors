import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

extension VersionVectorTests {
    internal func test_VersionVector_lessThan() throws {
        // Two empty version vectors should be considered equal instead of less than
        let emptyLeft: VersionVector = VersionVector()
        let emptyRight: VersionVector = VersionVector()
        (emptyLeft < emptyRight).shouldBeFalse()
        // Empty version vector is always less than non-empty
        (VersionVector() < VersionVector([(try self.replicaA.get(), VersionVector.Version(2))])).shouldBeTrue()
        // Every entry in lhs is <= rhs, and at least one is strictly less than
        (VersionVector([
            (try self.replicaA.get(), VersionVector.Version(1)),
            (try self.replicaB.get(), VersionVector.Version(2)),
        ])
            < VersionVector([
                (try self.replicaA.get(), VersionVector.Version(2)),
                (try self.replicaB.get(), VersionVector.Version(3)),
            ])).shouldBeTrue()
        // Not every entry in lhs is <= rhs
        (VersionVector([
            (try self.replicaA.get(), VersionVector.Version(1)),
            (try self.replicaB.get(), VersionVector.Version(3)),
        ])
            < VersionVector([
                (try self.replicaA.get(), VersionVector.Version(2)),
                (try self.replicaB.get(), VersionVector.Version(2)),
            ])).shouldBeFalse()
        // At least one entry in lhs must be strictly less than
        (VersionVector([
            (try self.replicaA.get(), VersionVector.Version(1)),
            (try self.replicaB.get(), VersionVector.Version(2)),
        ])
            < VersionVector([
                (try self.replicaA.get(), VersionVector.Version(2)),
                (try self.replicaB.get(), VersionVector.Version(2)),
            ])).shouldBeTrue()

    }

    internal func test_VersionVector_greaterThan() throws {
        let emptyLeft: VersionVector = VersionVector()
        let emptyRight: VersionVector = VersionVector()
        // Two empty version vectors should be considered equal instead of greater than
        (emptyLeft > emptyRight).shouldBeFalse()
        // Non-empty version vector is always greater than empty
        (VersionVector([(try self.replicaA.get(), VersionVector.Version(2))]) > VersionVector()).shouldBeTrue()
        // Every entry in lhs is >= rhs, and at least one is strictly greater than
        (VersionVector([
            (try self.replicaA.get(), VersionVector.Version(2)),
            (try self.replicaB.get(), VersionVector.Version(3)),
        ])
            > VersionVector([
                (try self.replicaA.get(), VersionVector.Version(1)),
                (try self.replicaB.get(), VersionVector.Version(2)),
            ])).shouldBeTrue()
        // Not every entry in lhs is >= rhs
        (VersionVector([
            (try self.replicaA.get(), VersionVector.Version(2)),
            (try self.replicaB.get(), VersionVector.Version(2)),
        ])
            > VersionVector([
                (try self.replicaA.get(), VersionVector.Version(1)),
                (try self.replicaB.get(), VersionVector.Version(3)),
            ])).shouldBeFalse()
        // At least one entry in lhs must be strictly greater than
        (VersionVector([
            (try self.replicaA.get(), VersionVector.Version(2)),
            (try self.replicaB.get(), VersionVector.Version(2)),
        ])
            > VersionVector([
                (try self.replicaA.get(), VersionVector.Version(1)),
                (try self.replicaB.get(), VersionVector.Version(2)),
            ])).shouldBeTrue()

    }

    internal func test_VersionVector_equality() throws {
        let emptyLeft: VersionVector = VersionVector()
        let emptyRight: VersionVector = VersionVector()
        // Two empty version vectors are considered equal
        (emptyLeft == emptyRight).shouldBeTrue()
        // Two version vectors should be considered equal if elements are equal
        (VersionVector([
            (try self.replicaA.get(), VersionVector.Version(2)),
            (try self.replicaB.get(), VersionVector.Version(1)),
        ])
            == VersionVector([
                (try self.replicaB.get(), VersionVector.Version(1)),
                (try self.replicaA.get(), VersionVector.Version(2)),
            ])).shouldBeTrue()
        (VersionVector() == VersionVector([(try self.replicaA.get(), VersionVector.Version(2))])).shouldBeFalse()
        (VersionVector([
            (try self.replicaA.get(), VersionVector.Version(2)),
            (try self.replicaB.get(), VersionVector.Version(3)),
        ])
            == VersionVector([
                (try self.replicaB.get(), VersionVector.Version(1)),
                (try self.replicaA.get(), VersionVector.Version(2)),
            ])).shouldBeFalse()

        // x = [A:1, B:4, C:6], y = [A:2, B:7, C:2]
        // x ≮ y, y ≮ x, x != y
        let vvX: VersionVector = VersionVector([
            (try self.replicaA.get(), VersionVector.Version(1)),
            (try self.replicaB.get(), VersionVector.Version(4)),
            (try self.replicaC.get(), VersionVector.Version(6)),
        ])
        let vvY: VersionVector = VersionVector([
            (try self.replicaA.get(), VersionVector.Version(2)),
            (try self.replicaB.get(), VersionVector.Version(7)),
            (try self.replicaC.get(), VersionVector.Version(2)),
        ])
        (vvX < vvY).shouldBeFalse()
        (vvY < vvX).shouldBeFalse()
        (vvX > vvY).shouldBeFalse()
        (vvY > vvX).shouldBeFalse()
        (vvX == vvY).shouldBeFalse()
    }
}
