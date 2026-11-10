// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO
import NIOSSL
import ServiceDiscovery
import SWIM

import class Foundation.ProcessInfo

extension ClusterSystemSettings {
    /// Prototype instrumentation mechanism settings.
    ///
    /// These can be used to inject implementations of instrumentation into the cluster system,
    /// which can emit metrics for a specific `ClusterSystem` sub-system when invoked.
    internal struct InstrumentationSettings {
        /// Default set of enabled instrumentations, based on current operating system.
        ///
        /// On Apple platforms, this includes the `OSSignpostInstrumentationProvider` provided instrumentations,
        /// as they carry only minimal overhead in release builds when the signposts are not active.
        ///
        /// Instrumentationを使わない場合は`.default`の代わりに`.disabled`を指定する。
        internal static var `default`: Self {
            .init()
        }

        /// no-opのinstrumentationを用いる設定。
        internal static var disabled: Self {
            Self()
        }

        /// - SeeAlso: `InternalActorTransportInstrumentation`
        internal var makeActorTransportInstrumentation: () -> InternalActorTransportInstrumentation = { () in
            NoopActorTransportInstrumentation()
        }

        /// - SeeAlso: `ReceptionistInstrumentation`
        internal var makeReceptionistInstrumentation: () -> ReceptionistInstrumentation = { () in
            NoopReceptionistInstrumentation()
        }

        internal mutating func configure(with provider: ClusterSystemInstrumentationProvider) {
            if let instrumentFactory = provider.actorTransportInstrumentation {
                self.makeActorTransportInstrumentation = instrumentFactory
            }

            if let instrumentFactory = provider.receptionistInstrumentation {
                self.makeReceptionistInstrumentation = instrumentFactory
            }
        }
    }
}
