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

import CDistributedActorsMailbox
import Foundation  // for Codable
import Logging
import NIO
import NIOFoundationCompat
import SwiftProtobuf

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Serializer

/// メッセージ型ごとのシリアライズ処理を定義する基底クラス。
open class Serializer<Message> {
    public init() {
        // Base serializers do not carry encoding state.
    }

    /// メッセージを実装固有のワイヤー形式へ符号化する。
    open func serialize(_: Message) throws -> Serialization.Buffer {
        undefined()
    }

    /// 実装固有のワイヤー形式からメッセージを復元する。
    open func deserialize(from _: Serialization.Buffer) throws -> Message {
        undefined()
    }

    /// Invoked _once_ by `Serialization` during system startup, providing additional context bound to
    /// the given `ClusterSystem` that enables certain system specific serialization operations, such as
    /// looking up actors.
    open func setSerializationContext(_: Serialization.Context) {
        // nothing by default, implementations may choose to not care
    }

    /// 符号化・復号で共有するユーザ情報を設定する。
    open func setUserInfo<Value>(key _: CodingUserInfoKey, value _: Value?) {
        // nothing by default, implementations may choose to not care
    }
}
