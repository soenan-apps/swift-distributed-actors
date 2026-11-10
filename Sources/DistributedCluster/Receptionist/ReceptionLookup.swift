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

/// 型消去した検出要求の共通表現。
public class ReceptionLookup: ReceptionistMessage, NotActuallyCodableMessage, @unchecked Sendable {
    internal let erasedKey: AnyReceptionKey

    internal init(erasedKey: AnyReceptionKey) {
        self.erasedKey = erasedKey
        super.init()
    }

    internal required init(from _: Decoder) throws {
        throw SerializationError(.nonTransportableMessage(type: "\(Self.self)"))
    }

    internal func replyWith(_: Set<AddressableActorRef>) {
        undefined()
    }

    internal func replyWith(_: [AddressableActorRef]) {
        undefined()
    }
}
