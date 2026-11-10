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

import DistributedCluster
import Foundation
import NIO
import NIOFoundationCompat

extension ParkingGarageStatus {
    internal typealias ProtobufRepresentation = _ProtoParkingGarageStatus

    internal enum ParkingGarageError: Error {
        case unknownStatusValue(Int)
    }

    internal init(fromProto proto: _ProtoParkingGarageStatus, context _: Serialization.Context) throws {
        switch proto.type {
        case .available:
            self = .available

        case .full:
            self = .full

        case .UNRECOGNIZED(let num):
            throw ParkingGarageError.unknownStatusValue(num)
        }
    }

    internal func toProto(context _: Serialization.Context) -> _ProtoParkingGarageStatus {
        var proto: _ProtoParkingGarageStatus = _ProtoParkingGarageStatus()
        switch self {
        case .available:
            proto.type = .available

        case .full:
            proto.type = .full
        }
        return proto
    }
}
