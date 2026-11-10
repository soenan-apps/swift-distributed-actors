// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

extension ActorID: PathRelationships {
    /// Actorの階層パスを構成する検証済みの各要素。
    public var segments: [ActorPathSegment] {
        self.path.segments
    }

    internal func makeChildID(name: String, incarnation: ActorIncarnation) throws -> ActorID {
        switch self.location {
        case let .local(node):
            return try .init(local: node, path: self.makeChildPath(name: name), incarnation: incarnation)

        case let .remote(node):
            return try .init(remote: node, path: self.makeChildPath(name: name), incarnation: incarnation)
        }
    }

    /// Creates a new path with `segment` appended
    public func appending(segment: ActorPathSegment) -> ActorID {
        switch self.location {
        case let .remote(node):
            return .init(remote: node, path: self.path.appending(segment: segment), incarnation: self.incarnation)

        case let .local(node):
            return .init(local: node, path: self.path.appending(segment: segment), incarnation: self.incarnation)
        }
    }
}
