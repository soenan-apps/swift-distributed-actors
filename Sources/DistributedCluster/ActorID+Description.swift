// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

extension ActorID: CustomStringConvertible {
    public var description: String {
        var res: String = ""
        if self.isRemote {
            res += "\(self.node)"
        }

        if let wellKnown = self.metadata.wellKnown {
            return "[$wellKnown: \(wellKnown)]"
        }

        if let path = self.metadata.path {
            // this is ready for making paths optional already -- and behavior removals
            res += "\(path)"
        } else {
            res += "\(self.incarnation)"
        }

        if !self.metadata.isEmpty {
            // we special case the "just a path" metadata to not break existing ActorRef tests
            if self.metadata.count == 1, self.metadata.path != nil {
                return res
            }

            res += self.metadata.description
        }

        return res
    }

    /// 所属ノード、パス、incarnationとmetadataを含めた診断用表現。
    public var detailedDescription: String {
        var res: String = ""
        if self.isRemote {
            res += "\(reflecting: self.node)"
        }
        res += "\(self.path)"

        if self.incarnation != ActorIncarnation.wellKnown {
            res += "#\(self.incarnation.value)"
        }

        if !self.metadata.isEmpty {
            res += self.metadata.description
        }

        return res
    }

    /// Prints all information contained in the ID, including `incarnation` and all `metadata`.
    public var fullDescription: String {
        var res: String = ""
        res += "\(reflecting: self.node)"
        res += "\(self.path)"
        res += "#\(self.incarnation.value)"

        if !self.metadata.isEmpty {
            res += self.metadata.description
        }

        #if DEBUG
        res += "{debugID:\(debugID)}"
        #endif

        return res
    }
}
