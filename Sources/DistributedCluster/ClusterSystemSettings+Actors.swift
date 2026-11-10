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
    /// Behaviorの実行に関する設定。
    public struct ActorSettings {
        /// Behaviorの実行に用いる既定の設定。
        public static var `default`: Self {
            .init()
        }

        /// Behaviorの開始・正規化で許容する入れ子数の上限。
        public var maxBehaviorNestingDepth: Int = 128
    }
}
