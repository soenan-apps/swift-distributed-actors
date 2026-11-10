// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

extension ActorID {
    /// incarnationの代わりに既知の名前で解決するIDかどうか。
    public var isWellKnown: Bool {
        self.metadata.wellKnown != nil
    }
}
