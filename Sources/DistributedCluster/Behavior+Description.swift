// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

extension Behavior: CustomStringConvertible {
    /// メッセージ型と現在の内部behaviorを含む文字列表現。
    public var description: String {
        let fqcn: String = String(reflecting: Behavior<Message>.self)
        return "\(fqcn).\(self.underlying)"
    }
}
