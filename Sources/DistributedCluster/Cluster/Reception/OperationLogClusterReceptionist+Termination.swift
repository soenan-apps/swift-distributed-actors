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

import CoreMetrics
import Logging

extension OperationLogClusterReceptionist {
    internal func onTerminated(context: ActorContext<ReceptionistMessage>, terminated: Signals.Terminated) {
        if terminated.id == ActorID.actorRefReceptionist(on: terminated.id.node, for: .actorRefs) {
            context.log.debug("Watched receptionist terminated: \(terminated)")
            self.onReceptionistTerminated(context, terminated: terminated)
        } else {
            context.log.debug("Watched actor terminated: \(terminated)")
            self.onActorTerminated(context, terminated: terminated)
        }
    }

    internal func onReceptionistTerminated(_ context: ActorContext<Message>, terminated: Signals.Terminated) {
        self.pruneClusterMember(context, removedNode: terminated.id.node)
    }

    internal func onActorTerminated(_ context: ActorContext<Message>, terminated: Signals.Terminated) {
        self.onActorTerminated(context, id: terminated.id)
    }

    internal func onActorTerminated(_ context: ActorContext<Message>, id: ActorID) {
        let equalityHackRef: ActorRef<Never> = ActorRef<Never>(.deadLetters(.init(context.log, id: id, system: nil)))
        let wasRegisteredWithKeys: ReceptionistStorage.RefMappingRemovalResult = self.storage.removeFromKeyMappings(
            equalityHackRef.asAddressable
        )

        for key in wasRegisteredWithKeys.registeredUnderKeys {
            self.addOperation(context, .remove(key: key, id: id))
            self.publishListings(context, forKey: key)
        }

        context.log.trace("Actor terminated \(id), and removed from receptionist.")
    }
}
