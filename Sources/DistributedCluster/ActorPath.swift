// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

/// Represents the name and placement within the actor hierarchy of a given actor.
///
/// Names of user actors MUST:
/// - not start with `$` (those names are reserved for Swift Distributed Actors internal system actors)
/// - contain only ASCII characters and select special characters (listed in `ValidPathSymbols.extraSymbols`)
///
/// - Example: `/user/lightbulbCommander/lightbulb-2012`
public struct ActorPath: PathRelationships, Hashable, Sendable, CustomStringConvertible, Comparable {
    /// Root of the actor hierarchy, represented by `/`.
    public static let root: ActorPath = .init()
    /// Root namespace for user actors.
    public static let userRoot: ActorPath = .init(validated: [.userRoot])
    /// Root namespace for system actors.
    public static let systemRoot: ActorPath = .init(validated: [.systemRoot])

    /// Ordered, validated segments comprising this path.
    public var segments: [ActorPathSegment]

    /// Returns the name of the actor represented by this path.
    /// This is equal to the last path segments string representation.
    public var name: String {
        // the only path which has no segments is the "root"
        let lastSegmentName: String = self.segments.last?.description ?? "/"
        return "\(lastSegmentName)"
    }

    /// Slash-separated representation of the path.
    public var description: String {
        let pathSegments: String = self.segments.map(\.value).joined(separator: "/")
        return "/\(pathSegments)"
    }

    /// Creates a path by validating its root segment.
    public init(root: String) throws {
        try self.init([ActorPathSegment(root)])
    }

    /// Creates a path from a nonempty collection of validated segments.
    public init(_ segments: [ActorPathSegment]) throws {
        guard !segments.isEmpty else {
            throw ActorPathError.illegalEmptyActorPath
        }
        self.segments = segments
    }

    /// Only the core module may define roots.
    internal init(root: ActorPathSegment) throws {
        try self.init([root])
    }

    /// Special purpose initializer, only for the "/" path. None other may use such path.
    private init() {
        self.segments = []
    }

    private init(validated segments: [ActorPathSegment]) {
        self.segments = segments
    }

    /// Orders actor paths by their slash-separated representation.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        "\(lhs)" < "\(rhs)"
    }

    /// Appends a segment to this actor path
    internal mutating func append(segment: ActorPathSegment) {
        self.segments.append(segment)
    }

    /// Appends a segment to this actor path
    public mutating func append(_ segment: String) throws {
        try self.segments.append(ActorPathSegment(segment))
    }

    /// Creates a new path with `segment` appended
    public func appending(segment: ActorPathSegment) -> Self {
        var path: Self = self
        path.append(segment: segment)
        return path
    }

    /// Creates a new path with `segment` appended
    public func appending(_ name: String) throws -> Self {
        try self.appending(segment: ActorPathSegment(name))
    }

    /// Creates a new path with a known-to-be-unique naming appended, otherwise faults
    internal func appendingKnownUnique(_ unique: ActorNaming) throws -> Self {
        guard case let .unique(name) = unique.naming else {
            fatalError("Expected known-to-be-unique ActorNaming in this unsafe call; Was: \(unique)")
        }
        return try self.appending(segment: ActorPathSegment(name))
    }

    /// Creates a new path with `segments` appended
    public func appending(segments: [ActorPathSegment]) -> Self {
        var path: Self = self
        for segment in segments {
            path.append(segment: segment)
        }
        return path
    }

    internal func makeLocalID(on node: Cluster.Node, incarnation: ActorIncarnation) -> ActorID {
        ActorID(local: node, path: self, incarnation: incarnation)
    }

    internal func makeRemoteID(on node: Cluster.Node, incarnation: ActorIncarnation) -> ActorID {
        ActorID(remote: node, path: self, incarnation: incarnation)
    }
}
