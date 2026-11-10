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

internal struct NetworkFaultGremlin {
    internal enum Directive {
        case drop
        case passThrough
    }

    internal let settings: FaultyNetworkSimulationSettings

    internal func decide() -> Directive {
        let randomNumber: Double = Double.random(in: 0.0...1.0)
        switch self.settings.mode {
        case .drop(let probability):
            return randomNumber < probability ? .drop : .passThrough
        }
    }
}
