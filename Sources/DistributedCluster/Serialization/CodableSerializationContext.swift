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

/// 符号化・復号処理にアクター参照の解決コンテキストを提供する。
public protocol CodableSerializationContext {
    /// コーダーに設定されたシリアライズコンテキスト。
    var actorSerializationContext: Serialization.Context? { get }
}
