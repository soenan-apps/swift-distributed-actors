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

import CoreMetrics

@usableFromInline
internal enum ActiveMetricID: Int, Hashable {
    case deserializationSize = 3
    case deserializationTime = 2
    case mailboxCount = 4
    case messageProcessingTime = 5
    case serializationSize = 1
    case serializationTime = 0
    internal typealias Timer = CoreMetrics.Timer

}
