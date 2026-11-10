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

internal enum Supervise {
    /// Supervision failure "catch all" selectors.
    /// By configuring supervision with one of the following you may configure a supervisor to catch only a specific
    /// type of failures (e.g. only swift `Error`s or only faults).
    ///
    /// See also supervision overloads which accept an `Error.Type` which allows you to specifically select an
    /// error type to supervise.
    internal enum All {
        case errors
        case failures
        case faults
    }
    internal enum AllErrors: Error {}

    internal enum AllFaults: Error {}

    internal enum AllFailures: Error {}
    // MARK: Phantom types for registering supervisors

    internal static func internalErrorTypeFor(selector: Self.All) -> Error.Type {
        switch selector {
        case .errors:
            return AllErrors.self

        case .faults:
            return AllFaults.self

        case .failures:
            return AllFailures.self
        }
    }
}
