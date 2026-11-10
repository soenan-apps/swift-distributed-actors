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

import Foundation
import XCTest

/// Whether assertion failures use terminal colors and source excerpts.
internal let kIsTty: Bool = isatty(fileno(stdin)) == 0

/// An error type with additional ``CallSiteInfo`` which is able to pretty print failures.
/// It is useful for printing complex failures on the command line and is usually thrown by `should` matchers.
public struct CallSiteError: Error, CustomStringConvertible {
    /// Location at which the assertion was applied.
    public let callSite: CallSiteInfo
    /// Explanation of the failed condition.
    public let explained: String

    /// Prepares a detailed error information
    ///
    /// - Warning: Performs file IO in order to read source location line where failure happened
    public var description: String {
        guard kIsTty else {
            return self.explained
        }

        var rendered: String = ""
        let source: String
        do {
            source = try String(contentsOfFile: "\(self.callSite.file)", encoding: .utf8)
        } catch {
            preconditionFailure("Unable to read assertion source: \(error)")
        }
        let sourceLines: [String] = source.components(separatedBy: .newlines)
        guard let failingLine = sourceLines.dropFirst(Int(self.callSite.line - 1)).first else {
            preconditionFailure("Assertion line must exist in its source file")
        }

        rendered += "\n"
        rendered += "\(failingLine)\n"
        let paddingCount: Int = Int(self.callSite.column) - 1 - self.callSite.appliedAssertionName.count
        rendered += String(repeating: " ", count: paddingCount)
        if kIsTty {
            rendered += ANSIColors.red.rawValue
        }
        rendered += "^\(String(repeating: "~", count: self.callSite.appliedAssertionName.count - 1))\n"
        rendered += "error: "
        rendered += self.explained
        rendered += ANSIColors.reset.rawValue

        return rendered
    }

    public init(callSite: CallSiteInfo, explained: String) {
        self.callSite = callSite

        self.explained = explained
    }

}
