// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2021 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed
import DistributedCluster
import Logging

internal enum ForkError: Error, Codable {
    case puttingBackNotTakenFork
}

internal distributed actor Fork: CustomStringConvertible {
    private lazy var log: Logger = {
        var logger: Logger = Logger(actor: self)
        logger[metadataKey: "name"] = "\(name)"
        return logger
    }()

    private let name: String
    private var isTaken: Bool = false

    internal init(name: String, actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        self.name = name
    }

    internal distributed func take() -> Bool {
        if self.isTaken {
            return false
        }

        self.isTaken = true
        return true
    }

    internal distributed func putBack() throws {
        guard self.isTaken else {
            self.log.error("Attempted to put back fork that was not taken!")
            throw ForkError.puttingBackNotTakenFork
        }
        self.isTaken = false
    }
}
