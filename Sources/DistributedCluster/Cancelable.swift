// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

@usableFromInline
internal protocol Cancelable {
    /// Returns true if the cancellable has already been cancelled, false otherwise.
    var isCanceled: Bool { get }

    /// Attempts to cancel the cancellable.
    func cancel()
}
