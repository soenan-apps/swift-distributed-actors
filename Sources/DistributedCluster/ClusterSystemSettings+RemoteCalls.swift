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
    /// 分散呼出のタイムアウトとエラー返却範囲を設定する。
    public struct RemoteCallSettings {
        /// 分散呼出に用いる既定の設定。
        public static var `default`: Self {
            .init()
        }

        /// If no other timeout is specified, this timeout is applied to every distributed call.
        ///
        /// Set to `.effectivelyInfinite` to avoid setting a timeout, although this is not recommended.
        public var defaultTimeout: Duration = .seconds(5)

        /// Codableエラーを元の型のまま返す範囲。
        public var codableErrorAllowance: CodableErrorAllowanceSettings = .all
    }
}
