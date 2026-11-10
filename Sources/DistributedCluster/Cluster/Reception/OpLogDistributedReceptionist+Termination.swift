// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import AsyncAlgorithms
import CoreMetrics
import Distributed
import Logging
import OrderedCollections

extension OpLogDistributedReceptionist {
    /// 登録されたactorまたはpeer receptionistの終了を反映する。
    public func terminated(actor id: ID) {
        if id == ActorID.actorRefReceptionist(on: id.node, for: .distributedActors) {
            self.log.debug("Watched receptionist terminated: \(id)")
            self.receptionistTerminated(identity: id)
        } else {
            self.log.debug("Watched actor terminated: \(id)")
            self.actorTerminated(id: id)
        }
    }

    internal func receptionistTerminated(identity id: ID) {
        self.pruneClusterMember(removedNode: id.node)
    }

    internal func actorTerminated(id: ID) {
        let wasRegisteredWithKeys: DistributedReceptionistStorage.RefMappingRemovalResult =
            self.storage.removeFromKeyMappings(id)

        // In case we manually caused an `actorTerminated` already, or if the actor
        // just was never registered to begin with, just ignore it completely and don't
        // even log this removal attempt; Can't remove something that wasn't added.
        guard !wasRegisteredWithKeys.registeredUnderKeys.isEmpty else {
            return
        }

        for key in wasRegisteredWithKeys.registeredUnderKeys {
            _ = self.addOperation(.remove(key: key, identity: id))
            self.publishListings(forKey: key)
        }

        self.log.trace("Actor terminated \(id), and removed from receptionist.")
    }
}
