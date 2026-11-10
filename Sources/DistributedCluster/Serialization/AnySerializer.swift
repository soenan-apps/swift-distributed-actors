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

/// Abstracts over different Encoder/Decoder and other serialization mechanisms.
///
/// Serializers may directly work on `NIO.ByteBuffer` or on `Foundation.Data`.
public protocol AnySerializer {
    /// 型を検査してメッセージを符号化する。
    func trySerialize(_ message: Any) throws -> Serialization.Buffer

    /// ワイヤー形式から型消去した値を復元する。
    func tryDeserialize(_ buffer: Serialization.Buffer) throws -> Any

    /// 符号化・復号に渡すユーザ情報を設定する。
    func setUserInfo<Value>(key: CodingUserInfoKey, value: Value?)
    /// アクター参照を解決するコンテキストを設定する。
    func setSerializationContext(_ context: Serialization.Context)
}
