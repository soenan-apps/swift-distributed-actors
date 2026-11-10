// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

import Dispatch

extension DispatchWorkItem: Cancelable {
    @usableFromInline internal var isCanceled: Bool {
        self.isCancelled
    }
}
