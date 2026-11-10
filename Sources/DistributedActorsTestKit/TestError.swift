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

import DistributedActorsConcurrencyHelpers
import Foundation
import Logging
import XCTest

@testable import DistributedCluster

/// Thrown when `ActorTestKit.eventually` cannot satisfy its assertion within the requested duration.
///
/// Intended to be pretty printed in command line test output.
public struct EventuallyError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    internal let callSite: CallSiteInfo
    internal let duration: Duration
    internal let polledTimes: Int
    internal let lastError: Error?

    public var description: String {
        var message: String = ""

        // This dance is necessary to "nicely print" if we had an embedded call site error,
        // which include colour and formatting, so we have to print the \(msg) directly for that case.
        let lastErrorMessage: String
        if let error = lastError {
            lastErrorMessage = "Last error: \(error)"
        } else {
            lastErrorMessage = "Last error: <none>"
        }

        message += """
            No result within \(self.duration.prettyDescription) for block \
            at \(self.callSite.file):\(self.callSite.line). \
            Queried \(self.polledTimes) times, within \(self.duration.prettyDescription). \
            \(lastErrorMessage)
            """

        return message
    }

    public var debugDescription: String {
        let error: Error = self.callSite.error(
            """
            Eventually block failed, after \(self.duration) (polled \(self.polledTimes) times), \
            last error: \(optional: self.lastError)
            """
        )
        return "\(error)"
    }

    internal init(_ callSite: CallSiteInfo, _ duration: Duration, _ polledTimes: Int, lastError: Error?) {
        self.callSite = callSite
        self.duration = duration
        self.polledTimes = polledTimes
        self.lastError = lastError
    }

}

/// Simple error type useful for failing tests / assertions
public struct TestError: Error, Hashable {
    /// Failure description supplied by the assertion.
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}
