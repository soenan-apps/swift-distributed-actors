// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

extension Props {
    internal static func singletonInstance(settings: ClusterSingletonSettings) -> Props {
        Props().singletonInstance(settings: settings)
    }

    internal func singletonInstance(settings: ClusterSingletonSettings) -> Props {
        var props: Props = self
        props.knownActorName = settings.name
        props.wellKnownName = settings.name
        return props
    }
}
