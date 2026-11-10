// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

import Dispatch

extension DispatchTime {
    internal init(nowDelayedBy delay: Duration) {
        self.init(uptimeNanoseconds: Self.now().uptimeNanoseconds + UInt64(delay.nanoseconds))
    }
}
