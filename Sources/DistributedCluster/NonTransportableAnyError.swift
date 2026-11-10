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

/// Useful error wrapper which performs an best effort Error serialization as configured by the actor system.
public struct NonTransportableAnyError: Error, NotActuallyCodableMessage {
    /// The original local error.
    public let failure: Error

    /// Retains the failure without making its payload transportable.
    public init<Failure: Error>(_ failure: Failure) {
        self.failure = failure
    }
}
