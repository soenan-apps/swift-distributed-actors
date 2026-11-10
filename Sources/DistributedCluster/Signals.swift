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

/// システムチャネルで配送するライフサイクル通知。新しい通知型はユーザが実装しない。
/// 通常のメッセージと異なり、トランスポートは通知を破棄しない。
public protocol Signal: NotActuallyCodableMessage, Sendable {}

/// Actorシステムが生成するライフサイクル通知。
public enum Signals {
    /// 失敗したBehaviorを置換する直前に配送する。処理失敗時は再起動せず終了する。
    public struct PreRestart: Signal {
        @usableFromInline
        internal init() {
            // ペイロードのないライフサイクル通知。
        }
    }

    /// Actorが停止した後に配送する。ハンドラが返すBehaviorは無視する。
    public struct PostStop: Sendable, Signal {
        @usableFromInline
        internal init() {
            // ペイロードのないライフサイクル通知。
        }
    }

    /// 監視対象のActorまたは所属ノードが終了したことを通知する。
    /// トランスポートは追加情報を表すために継承できる。
    open class Terminated: @unchecked Sendable, Signal, CustomStringConvertible, Equatable, Hashable {
        /// 終了したActorのアドレス。
        public let id: ActorID

        /// 終了したdistributed actorの識別子。
        public var identity: ActorID {
            self.id
        }

        /// 終了前にActorの存在を確認できたかどうか。
        public let existenceConfirmed: Bool

        /// ノード全体の終了による通知かどうか。
        public let nodeTerminated: Bool

        /// トランスポートが調整できる通知の説明。
        open var description: String {
            "Terminated(\(self.id), existenceConfirmed: \(self.existenceConfirmed))"
        }

        /// 終了通知を作る。nodeTerminatedは現在の実装では使用しない。
        public init(id: ActorID, existenceConfirmed: Bool, nodeTerminated _: Bool = false) {
            self.id = id
            self.existenceConfirmed = existenceConfirmed
            self.nodeTerminated = false
        }

        public static func == (lhs: Terminated, rhs: Terminated) -> Bool {
            lhs.id == rhs.id && lhs.existenceConfirmed == rhs.existenceConfirmed
        }

        public func hash(into hasher: inout Hasher) {
            self.id.hash(into: &hasher)
            self.existenceConfirmed.hash(into: &hasher)
        }
    }

    /// 子Actorの終了を親へ必ず配送し、escalateされた失敗を伝える。
    /// watchしていない子の終了はdeath pactを起こさない。
    internal final class ChildTerminated: Terminated, @unchecked Sendable {
        /// 子を終了させた失敗。親以外には公開しない。
        internal let escalation: Supervision.Failure?

        override internal var description: String {
            let reason: String
            if case .some(let failure) = self.escalation {
                reason = ", escalation: \(failure)"
            } else {
                reason = ""
            }
            return "_ChildTerminated(\(self.id)\(reason))"
        }

        internal init(id: ActorID, escalation: Supervision.Failure?) {
            self.escalation = escalation
            super.init(id: id, existenceConfirmed: true)
        }
    }
}
