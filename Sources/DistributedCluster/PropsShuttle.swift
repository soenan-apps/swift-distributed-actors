// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0. See LICENSE.txt and CONTRIBUTORS.txt.
// SPDX-License-Identifier: Apache-2.0

/// Carries spawn properties into an actor ID during identity assignment; never serialized.
internal struct PropsShuttle: @unchecked Sendable, NotActuallyCodableMessage {
    internal let props: Props

    internal init(props: Props) {
        self.props = props.deepCopy()
    }
}
