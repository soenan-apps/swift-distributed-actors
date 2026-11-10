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

extension Props {
    /// Creates a new `Props` appending a supervisor for the selected `Error` type, useful for setting a few
    /// options in-line when spawning actors.
    ///
    /// Note that order in which overlapping selectors/types are added to the chain matters.
    ///
    /// - Parameters:
    ///   - strategy: supervision strategy to apply for the given class of failures
    /// - forErrorType: error type selector, determining for what type of error the given supervisor should
    /// perform its logic.
    internal static func supervision(strategy: SupervisionStrategy, forErrorType errorType: Error.Type) -> Props {
        var props: Props = Props()
        props.supervise(strategy: strategy, forErrorType: errorType)
        return props
    }

    /// Creates a new `Props` appending a supervisor for the selected failure type, useful for setting a few
    /// options in-line when spawning actors.
    ///
    /// Note that order in which overlapping selectors/types are added to the chain matters.
    ///
    /// - Parameters:
    ///   - strategy: supervision strategy to apply for the given class of failures
    ///   - forAll: failure type selector, working as a "catch all" for the specific types of failures.
    internal static func supervision(
        strategy: SupervisionStrategy,
        forAll selector: Supervise.All = .failures
    ) -> Props {
        self.supervision(strategy: strategy, forErrorType: Supervise.internalErrorTypeFor(selector: selector))
    }

    /// Creates a new `Props` appending a supervisor for the selected `Error` type, useful for setting a few
    /// options in-line when spawning actors.
    ///
    /// Note that order in which overlapping selectors/types are added to the chain matters.
    ///
    /// - Parameters:
    ///   - strategy: supervision strategy to apply for the given class of failures
    /// - forErrorType: error type selector, determining for what type of error the given supervisor should
    /// perform its logic.
    internal func supervision(strategy: SupervisionStrategy, forErrorType errorType: Error.Type) -> Props {
        var props: Props = self
        props.supervise(strategy: strategy, forErrorType: errorType)
        return props
    }

    /// Creates a new `Props` appending a supervisor for the selected failure type, useful for setting a few
    /// options in-line when spawning actors.
    ///
    /// Note that order in which overlapping selectors/types are added to the chain matters.
    ///
    /// - Parameters:
    ///   - strategy: supervision strategy to apply for the given class of failures
    ///   - forAll: failure type selector, working as a "catch all" for the specific types of failures.
    internal func supervision(strategy: SupervisionStrategy, forAll selector: Supervise.All = .failures) -> Props {
        self.supervision(strategy: strategy, forErrorType: Supervise.internalErrorTypeFor(selector: selector))
    }

    /// Adds another supervisor for the selected `Error` type to the chain of existing supervisors in this `Props`.
    ///
    /// Note that order in which overlapping selectors/types are added to the chain matters.
    ///
    /// - Parameters:
    ///   - strategy: supervision strategy to apply for the given class of failures
    ///   - forErrorType: failure type selector, working as a "catch all" for the specific types of failures.
    internal mutating func supervise(strategy: SupervisionStrategy, forErrorType errorType: Error.Type) {
        self.supervision.add(strategy: strategy, forErrorType: errorType)
    }

    /// Adds another supervisor for the selected failure type to the chain of existing supervisors in this `Props`.
    ///
    /// Note that order in which overlapping selectors/types are added to the chain matters.
    ///
    /// - Parameters:
    ///   - strategy: supervision strategy to apply for the given class of failures
    ///   - forAll: failure type selector, working as a "catch all" for the specific types of failures.
    internal mutating func supervise(strategy: SupervisionStrategy, forAll selector: Supervise.All = .failures) {
        self.supervise(strategy: strategy, forErrorType: Supervise.internalErrorTypeFor(selector: selector))
    }

}
