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

import Logging

/// Represents an entity that is able to register with the `Receptionist`.
///
/// It is either an `ActorRef<Message>`.
public protocol ReceptionistGuest {
    /// 登録対象のアクターが受信するメッセージ型。
    associatedtype Message: Codable

    /// 登録対象の型付きアクター参照。
    var ref: ActorRef<Message> { get }
}
