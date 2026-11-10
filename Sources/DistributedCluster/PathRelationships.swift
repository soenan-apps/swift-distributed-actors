// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

/// Actorの階層パスに対する、要素単位の比較と追加操作。
public protocol PathRelationships {
    /// Individual segments of the `ActorPath`.
    var segments: [ActorPathSegment] { get }
    /// 検証済みの要素を追加したパスを返す。
    func appending(segment: ActorPathSegment) -> Self
}

extension PathRelationships {
    /// Combines the base path with a child segment returning the concatenated path.
    internal static func / (base: Self, child: ActorPathSegment) -> Self {
        base.appending(segment: child)
    }

    /// Checks whether this path starts with the passed in `path`.
    public func starts(with path: ActorPath) -> Bool {
        self.segments.starts(with: path.segments)
    }

    /// パスの要素だけで、指定したパスの直下にあるかどうかを判定する。
    /// Actorのincarnationや実際の親子関係は判定しない。
    public func isChildPathOf(_ maybeParentPath: PathRelationships) -> Bool {
        self.segments.dropLast().elementsEqual(maybeParentPath.segments)
    }

    /// パスの要素だけで、指定したパスの直上にあるかどうかを判定する。
    /// Actorのincarnationや実際の親子関係は判定しない。
    public func isParentOf(_ maybeChildPath: PathRelationships) -> Bool {
        maybeChildPath.isChildPathOf(self)
    }

    /// Create a generic path to identify a child path of the current path.
    internal func makeChildPath(name: String) throws -> ActorPath {
        try ActorPath(self.segments).appending(name)
    }
}
