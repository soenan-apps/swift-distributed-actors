// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO

extension ActorShell: CustomStringConvertible {
    @usableFromInline internal var asAddressable: AddressableActorRef {
        self.myself.asAddressable
    }

    internal var systemMessageReceiver: ReceivesSystemMessages {
        self.myself
    }

    public var description: String {
        let prettyTypeName: String = String(reflecting: Message.self)
            .split(separator: ".").dropFirst().joined(separator: ".")
        return "ActorContext<\(prettyTypeName)>(\(self.path))"
    }
}
