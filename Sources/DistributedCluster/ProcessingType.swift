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

/// Used in `Supervisor` to determine what type of processing caused the failure
///
/// - start: failure happened during actor (re-)starting, for example an error was thrown in an initial `.setup`
/// - message: failure happened during message processing
/// - signal: failure happened during signal processing
/// - closure: failure happened during closure processing
@usableFromInline
internal enum ProcessingType {
    case closure
    case continuation
    case message
    case signal
    case start
    case subMessage
}
