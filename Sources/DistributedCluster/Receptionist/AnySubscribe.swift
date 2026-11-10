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

internal struct AnySubscribe: Hashable {
    internal let id: ActorID
    internal let reply: (Set<AddressableActorRef>) -> Void

    internal init<Guest>(subscribe: Receptionist.Subscribe<Guest>) where Guest: ReceptionistGuest {
        self.id = subscribe.subscriber.id
        self.reply = subscribe.replyWith
    }

    internal init(id: ActorID) {
        self.id = id
        self.reply = { _ in () }
    }

    internal static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    internal func replyWith(_ refs: Set<AddressableActorRef>) {
        self.reply(refs)
    }

    internal func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}
