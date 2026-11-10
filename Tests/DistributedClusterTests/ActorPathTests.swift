// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import XCTest

@testable import DistributedCluster

internal final class ActorPathTests: XCTestCase {
    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: ActorPath

    internal func test_shouldNotAllow_illegalCharacters() throws {
        try shouldThrow(expected: ActorPathError.self) {
            _ = try ActorPath(root: "")
        }
        try shouldThrow(expected: ActorPathError.self) {
            _ = try ActorPath(root: " ")
        }
    }

    internal func test_pathsWithSameSegments_shouldBeEqual() throws {
        let pathA: ActorPath = try ActorPath(root: "test") / ActorPathSegment("foo") / ActorPathSegment("bar")
        let pathB: ActorPath = try ActorPath(root: "test") / ActorPathSegment("foo") / ActorPathSegment("bar")

        pathA.shouldEqual(pathB)
    }

    internal func test_pathsWithSameSegments_shouldHaveSameHasCode() throws {
        let pathA: ActorPath = try ActorPath(root: "test") / ActorPathSegment("foo") / ActorPathSegment("bar")
        let pathB: ActorPath = try ActorPath(root: "test") / ActorPathSegment("foo") / ActorPathSegment("bar")

        pathA.hashValue.shouldEqual(pathB.hashValue)
    }

    internal func test_path_shouldRenderNicely() throws {
        let pathA: ActorPath = try ActorPath(root: "test") / ActorPathSegment("foo") / ActorPathSegment("bar")
        pathA.description.shouldEqual("/test/foo/bar")
    }

    internal func test_pathName_shouldRenderNicely() throws {
        let pathA: ActorPath = try ActorPath(root: "test") / ActorPathSegment("foo") / ActorPathSegment("bar")

        pathA.name.description.shouldEqual("bar")
    }

    internal func test_rootPath_shouldRenderAsExpected() {
        let rootPath: ActorPath = ActorPath.root

        "\(rootPath)".shouldEqual("/")
        rootPath.name.shouldEqual("/")
    }

    internal func test_path_startsWith() throws {
        let path: ActorPath = try ActorPath(root: "test").appending("foo").appending("bar")
        path.starts(with: path).shouldBeTrue()  // fixme consistency of matchers, some throw and some not
        try path.starts(with: path.appending("nope")).shouldBeFalse()
        try path.starts(with: ActorPath(root: "test").appending("foo").appending("nope")).shouldBeFalse()
        try path.starts(with: ActorPath(root: "test").appending("nein").appending("bar")).shouldBeFalse()
        try path.starts(with: ActorPath(root: "test").appending("foo")).shouldBeTrue()
        try path.starts(with: ActorPath(root: "test")).shouldBeTrue()
        path.starts(with: ActorPath.root).shouldBeTrue()

        ActorPath.root.starts(with: ActorPath.root).shouldBeTrue()
    }
}
