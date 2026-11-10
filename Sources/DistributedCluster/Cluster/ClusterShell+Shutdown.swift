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

import CoreMetrics
import DistributedActorsConcurrencyHelpers
import Logging
import NIO
import SWIM

extension ClusterShell {
    internal func onShutdownCommand(
        _ context: ActorContext<Message>,
        state: ClusterShellState,
        signalOnceUnbound: BlockingReceptacle<Void>
    ) -> Behavior<Message> {
        // Remove death-pacts before shutting children down.
        // swift-format-ignore: ReplaceForEachWithForLoop
        context.children.forEach { ref in
            context.unwatch(ref)
        }

        let addrDesc: String = "\(state.settings.bindNode.endpoint.host):\(state.settings.bindNode.endpoint.port)"
        return context.awaitResult(
            of: state.channel.close(), timeout: context.system.settings.unbindTimeout
        ) { result in
            switch result {
            case .success:
                context.log.info("Unbound server socket [\(addrDesc)], node: \(reflecting: state.selfNode)")
                self.serializationPool.shutdown()
                signalOnceUnbound.offerOnce(())
                return .stop

            case .failure(let err):
                context.log.warning(
                    """
                    Failed while unbinding server socket [\(addrDesc)], \
                    node: \(reflecting: state.selfNode). Error: \(err)
                    """
                )
                self.serializationPool.shutdown()
                signalOnceUnbound.offerOnce(())
                throw err
            }
        }
    }
}
