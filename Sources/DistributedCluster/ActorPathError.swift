// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

internal enum ActorPathError: Error {
    case illegalActorPathElement(name: String, illegal: String, index: Int)
    case illegalEmptyActorPath
    case illegalLeadingSpecialCharacter(name: String, illegal: Character)
    case invalidPath(String)
    case rootPathSegmentRequiredToStartWithSlash(segment: ActorPathSegment)
}
