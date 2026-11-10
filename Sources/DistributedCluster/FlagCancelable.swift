// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

import Atomics

internal final class FlagCancelable: Cancelable, @unchecked Sendable {
    private let flag: ManagedAtomic<Bool> = .init(false)

    @usableFromInline internal var isCanceled: Bool {
        self.flag.load(ordering: .relaxed)
    }

    internal func cancel() {
        _ = self.flag.compareExchange(expected: false, desired: true, ordering: .relaxed)
    }
}
