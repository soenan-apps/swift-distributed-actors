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

internal final class ReceptionistListingFlushTick: ReceptionistMessage,
    NotActuallyCodableMessage, @unchecked Sendable {
    internal let key: AnyReceptionKey

    internal init(key: AnyReceptionKey) {
        self.key = key
        super.init()
    }

    internal required init(from _: Decoder) throws {
        throw SerializationError(.nonTransportableMessage(type: "\(Self.self)"))
    }
}
