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

import Distributed

import struct Foundation.Data

extension DistributedActor where ActorSystem == ClusterSystem {
    /// Behavior APIで用いる分散呼出のメッセージ型。
    public typealias Message = InvocationMessage

    internal static func makeBehavior(instance _: Self) -> Behavior<Message> {
        .receive { _, message in
            fatalError("EXECUTE: \(message)")
        }
    }

    internal static func spawnAny(instance: Self, on system: ActorSystem) throws -> AddressableActorRef {
        try self.spawn(instance: instance, on: system).asAddressable
    }

    /// Actor instanceに対応するBehavior actorを生成し、生成に失敗した場合はそのエラーを返す。
    public static func spawn(instance: Self, on system: ActorSystem) throws -> ActorRef<Message> {
        let behavior: Behavior<InvocationMessage> = makeBehavior(instance: instance)

        return try system.spawn(ActorNaming.prefixed(with: "\(Self.self)"), behavior)
    }
}
