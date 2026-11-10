// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Logging

/// メッセージ型にかかわらずsubReceiveのキーを保持する。
public struct AnySubReceiveId: Hashable, Equatable {
    internal let underlying: AnyHashable

    internal init<SubMessage>(_ id: SubReceiveId<SubMessage>) {
        self.underlying = AnyHashable(id)
    }
}
