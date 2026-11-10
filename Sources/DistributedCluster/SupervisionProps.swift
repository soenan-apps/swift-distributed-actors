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

/// Properties configuring supervision for given actor.
internal struct SupervisionProps {
    internal static let `default`: SupervisionProps = .init()
    // on purpose stored as list, to keep order in which the supervisors are added as we "scan" from first to
    // last when we handle
    internal var supervisionMappings: [ErrorTypeBoundSupervisionStrategy]

    internal init() {
        self.supervisionMappings = []
    }

    /// Add another supervision strategy for a specific `Error` type to the supervision chain contained within
    /// these props.
    ///
    /// - SeeAlso: The `Supervise.All.*` wildcard failure  type selectors may be used for the `forErrorType` parameter.
    internal mutating func add(strategy: SupervisionStrategy, forErrorType errorType: Error.Type) {
        self.supervisionMappings.append(ErrorTypeBoundSupervisionStrategy(failureType: errorType, strategy: strategy))
    }

    /// Non mutating version of `SupervisionProps.add(strategy:forErrorType:)`
    ///
    /// - SeeAlso: The `Supervise.All.*` wildcard failure  type selectors may be used for the `forErrorType` parameter.
    internal func adding(strategy: SupervisionStrategy, forErrorType errorType: Error.Type) -> Self {
        var props: Self = self
        props.add(strategy: strategy, forErrorType: errorType)
        return props
    }
}
