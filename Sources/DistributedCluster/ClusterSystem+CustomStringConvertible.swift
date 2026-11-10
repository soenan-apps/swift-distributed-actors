// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

extension ClusterSystem: CustomStringConvertible {
    public var description: String {
        var descriptionText: String = "ClusterSystem("
        descriptionText.append(self.name)
        if self.settings.enabled {
            descriptionText.append(", \(self.cluster.node)")
        }
        descriptionText.append(")")
        return descriptionText
    }
}
