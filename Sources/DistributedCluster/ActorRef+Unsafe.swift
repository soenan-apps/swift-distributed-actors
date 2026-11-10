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

import Distributed
import struct NIO.ByteBuffer
import protocol NIO.EventLoop

extension ActorRef {
    /// UNSAFE API, DO NOT TOUCH.
    /// This may only be used when certain that a given ref points to a local actor, and thus contains a cell.
    /// May be used by internals when things are to be attached to "myself's cell".
    @usableFromInline internal var unsafeUnwrapCell: ActorCell<Message> {
        switch self.personality {
        case .cell(let cell):
            return cell

        default:
            fatalError("""
                Illegal downcast attempt from \(String(reflecting: self)) to _ActorRefWithCell. This \
                is a Swift Distributed Actors bug, please report this on the issue tracker.
                """)
        }
    }

    @usableFromInline internal var unwrapActorMetrics: ActiveActorMetrics {
        switch self.personality {
        case .cell(let cell):
            return cell.actor?.metrics ?? ActiveActorMetrics.noop

        default:
            return ActiveActorMetrics.noop
        }
    }

    @usableFromInline internal var unsafeUnwrapRemote: RemoteClusterActorPersonality<Message> {
        switch self.personality {
        case .remote(let remote):
            return remote

        default:
            fatalError("""
                Illegal downcast attempt from \(String(reflecting: self)) to _ActorRefWithCell. This \
                is a Swift Distributed Actors bug, please report this on the issue tracker.
                """)
        }
    }
}
