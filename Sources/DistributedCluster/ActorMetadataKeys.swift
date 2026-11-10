// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

/// ActorIDのmetadataに使用する型付きキーの名前空間。
public struct ActorMetadataKeys {
    /// キーに対応する値の型を表す。
    public typealias Key = ActorMetadataKey

    internal struct ActorTypeTagValue: Codable, CustomStringConvertible {
        internal let mangledName: String
        internal var simpleName: String {
            _typeByName(self.mangledName).map { "\($0)" } ?? self.mangledName
        }

        internal var description: String {
            self.simpleName
        }
    }

    /// key pathを使用するmetadata APIの基点。
    internal static var defaultInstance: Self { .init() }

    internal var path: Key<ActorPath> { "$path" }

    /// incarnationの交換なしで既知のActorを解決するための名前。
    /// 通常のActorには使用せず、クラスタの既知サービスに限定する。
    public var wellKnown: Key<String> { "$wellKnown" }

    internal var knownActorName: Key<String> { "$wellKnownName" }
    internal var actorProps: Key<PropsShuttle> { "$props" }
    internal var type: Key<ActorTypeTagValue> { "$type" }

    private init() {
        // 名前空間のインスタンスはkey pathの評価にのみ使用する。
    }
}
