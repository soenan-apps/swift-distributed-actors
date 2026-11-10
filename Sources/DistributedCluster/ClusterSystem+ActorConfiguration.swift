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

extension ClusterSystem {
    /// Allows creating a distributed actor with additional configuration applied during its initialization.
    internal func actorWith<Act: DistributedActor>(
        props: Props? = nil,
        _ makeActor: () throws -> Act
    ) rethrows -> Act {
        guard let props = props else {
            return try makeActor()
        }

        return try Props.$forSpawn.withValue(props) {
            try makeActor()
        }
    }

    internal func interceptCalls<Act, Interceptor>(
        to _: Act.Type,
        metadata _: ActorMetadata,
        interceptor: Interceptor
    ) throws -> Act
    where
        Act: DistributedActor,
        Act.ActorSystem == ClusterSystem,
        Interceptor: RemoteCallInterceptor {
        // Prepare a distributed actor context base, such that the reserved ID will contain the interceptor
        // in the context.
        let baseContext: DistributedActorContext = DistributedActorContext(
            lifecycle: nil,
            remoteCallInterceptor: interceptor
        )
        var id: ActorID = self.assignID(Act.self, baseContext: baseContext)
        assert(id.context.remoteCallInterceptor != nil)
        id = id.asRemote

        var props: Props = Props()
        props.designatedActorID = id

        return try Act.resolve(id: id, using: self)
    }
}
