// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed

internal distributed actor ClusterDaemonServant {
    internal typealias ActorSystem = ClusterSystem

    @ActorID.Metadata(\.wellKnown)
    internal var wellKnownName: String

    internal init(system: ClusterSystem) async {
        self.actorSystem = system
        self.wellKnownName = "$cluster-daemon-servant"
    }
}
