// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

internal enum StopReason {
    /// The actor experienced a failure that was not handled by supervision.
    case failure(Supervision.Failure)
    /// A stop was requested by the parent, i.e. `context.stop(child:)`.
    case stopByParent
    /// The actor decided to stop and returned `Behavior.stop`.
    case stopMyself
}
