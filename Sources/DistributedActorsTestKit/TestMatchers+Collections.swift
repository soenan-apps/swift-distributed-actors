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

extension TestMatchers where T: Collection, T.Element: Equatable {
    /// Asserts that `value` starts with the passed in `prefix`.
    ///
    /// A prefix mismatch includes the matching sub-prefix so the first difference is easier to locate.
    public func toStartWith<PossiblePrefix>(prefix: PossiblePrefix)
    where PossiblePrefix: Collection, T.Element == PossiblePrefix.Element {
        if !self.value.starts(with: prefix) {
            let partialMatch: T.SubSequence = self.value.commonPrefix(with: prefix)
            // fancy printout:
            var message: String = "Expected "
            if kIsTty {
                message += "[\(ANSIColors.bold.rawValue)"
            }
            message += "\(partialMatch)"
            if kIsTty {
                message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            }
            message += "\(self.value.dropFirst(partialMatch.underestimatedCount))] "
            message += "to start with prefix: "
            if kIsTty {
                message += "\n"
            }
            if kIsTty {
                message += String(repeating: " ", count: "[error] Expected ".count)
            }  // align with the error message prefix
            message += "["
            if kIsTty {
                message += "\(ANSIColors.bold.rawValue)"
            }
            message += "\(partialMatch)"
            if kIsTty {
                message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            }
            message += "\(prefix.dropFirst(partialMatch.underestimatedCount))]."
            if kIsTty {
                message +=
                    " (Matching sub-prefix marked in \(ANSIColors.bold.rawValue)bold"
                    + "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue))"
            }
            let error: CallSiteError = self.callSite.error(message)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts that `value` ends with the passed in `suffix`.
    public func toEndWith<PossibleSuffix>(suffix: PossibleSuffix)
    where PossibleSuffix: Collection, T.Element == PossibleSuffix.Element {
        if !self.value.reversed().starts(with: suffix.reversed()) {
            let prefix: T.SubSequence = self.value.prefix(self.value.count - suffix.count)
            // fancy printout:
            var message: String = "Expected "
            if kIsTty {
                message += "["
            }
            message += "\(prefix)"
            message += "\(ANSIColors.bold.rawValue)"
            let itSuffix: String = self.value.reversed().prefix(suffix.count).reversed()
                .reduce(into: "") { $0 += "\($1)" }
            message += "\(itSuffix)"
            if kIsTty {
                message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            }
            message += "] to end with suffix: "
            if kIsTty {
                message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            }
            message += "\(ANSIColors.bold.rawValue)"
            message += "\(suffix)\n"
            message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            if kIsTty {
                message += String(repeating: " ", count: "[error] Expected".count)
            }  // align with the error message prefix
            message += "[\(String(repeating: ".", count: prefix.count))"
            message += "\(ANSIColors.red.rawValue)\(ANSIColors.bold.rawValue)"
            message += "\(suffix)"
            message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            message += "]"
            message += "\(ANSIColors.reset.rawValue)"
            let error: CallSiteError = self.callSite.error(message)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts that `value` contains the `element` element.
    public func toContain(_ element: T.Element) {
        if !self.value.contains(element) {
            // fancy printout:
            var message: String = "Expected \(T.self):\n    "
            message += self.value.map { "\($0)" }.joined(separator: "\n    ")
            message += "\n"
            message += "to contain: ["
            if kIsTty {
                message += "\(ANSIColors.bold.rawValue)"
            }
            message += "\(element)"
            if kIsTty {
                message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            }
            message += "]"
            let error: CallSiteError = self.callSite.error(message)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts that the collection excludes the element.
    public func toNotContain(_ element: T.Element) {
        if self.value.contains(element) {
            // fancy printout:
            var message: String = "Expected \(T.self):\n    "
            message += self.value.map { "\($0)" }.joined(separator: "\n    ")
            message += "\n"
            message += "to NOT contain: ["
            if kIsTty {
                message += "\(ANSIColors.bold.rawValue)"
            }
            message += "\(element)"
            if kIsTty {
                message += "\(ANSIColors.reset.rawValue)\(ANSIColors.red.rawValue)"
            }
            message += "]"
            let error: CallSiteError = self.callSite.error(message)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }

    /// Asserts that `value` contains at least one element matching the predicate.
    public func toContain(where predicate: (T.Element) -> Bool) {
        if !self.value.contains(where: { element in predicate(element) }) {
            // fancy printout:
            let message: String = "Expected [\(value)] to contain element matching predicate"
            let error: CallSiteError = self.callSite.error(message)
            XCTFail("\(error)", file: self.callSite.file, line: self.callSite.line)
        }
    }
}
