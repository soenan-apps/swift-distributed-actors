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

internal struct FaultyNetworkSimulationSettings {
    internal enum Mode {
        /// Drop messages with given probability
        case drop(probability: Double)

    }

    /// Mode in which the gremlin shall interfere with the communication.
    internal var mode: Mode

    /// Transform the message before logging it when it is being dropped or delayed.
    internal var formatMessage: (Any) -> Any = { any in
        any
    }

    /// String added before the output but after IN or OUT when a delay/drop is directed.
    internal var label: String?
    internal var effectiveLabel: String {
        if let configuredLabel = self.label {
            return configuredLabel
        }
        switch self.mode {
        case .drop:
            return "(DROP)"
        }
    }

    /// At what level should all DROP or similar operations be logged?
    internal var logLevel: Logger.Level?

    internal init(mode: Mode) {
        self.mode = mode
    }
}
