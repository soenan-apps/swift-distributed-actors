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

/// INTERNAL API
public class AnyReceptionRegistration: ReceptionistMessage, NotActuallyCodableMessage,
    CustomStringConvertible, @unchecked Sendable {
    internal var addressableActorRef: AddressableActorRef { undefined() }
    internal var erasedKey: AnyReceptionKey { undefined() }

    public var description: String {
        "Receptionist._Register(addressableActorRef: \(self.addressableActorRef), erasedKey: \(self.erasedKey))"
    }

    internal func replyRegistered() {
        undefined()
    }

}
