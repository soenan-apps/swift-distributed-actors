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

import Foundation

/// INTERNAL API: May change without any prior notice.
internal struct ResolveContext<Message: Codable> {
    /// The "remaining path" of the resolve being performed
    internal var selectorSegments: ArraySlice<ActorPathSegment>

    /// Address that we are trying to resolve.
    internal var id: ActorID

    internal let system: ClusterSystem

    /// Allows carrying metadata from Coder
    internal let userInfo: [CodingUserInfoKey: Any]
    /// Returns copy of traversal context yet "one level deeper."
    ///
    /// Note that this also drops the `path` if it was present, but retains the `incarnation` as we may want to resolve
    /// a _specific_ ref after all.
    internal var deeper: Self {
        var next: Self = self
        next.selectorSegments = self.selectorSegments.dropFirst()
        return next
    }

    /// A dead letters reference that is personalized for the context's address, and well  well typed for `Message`.
    internal var personalDeadLetters: ActorRef<Message> {
        self.system.personalDeadLetters(recipient: self.id)
    }

    internal init(id: ActorID, system: ClusterSystem, userInfo: [CodingUserInfoKey: Any] = [:]) {
        self.id = id
        self.selectorSegments = id.path.segments[...]
        self.system = system
        self.userInfo = userInfo
    }
}
