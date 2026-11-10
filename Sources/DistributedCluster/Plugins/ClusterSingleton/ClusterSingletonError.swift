// Copyright (c) 2019-2022 Apple Inc. and the Swift Distributed Actors project authors
// SPDX-License-Identifier: Apache-2.0

internal enum ClusterSingletonError: Error, Codable {
    case allocationTimeout
    case bufferCapacityExceeded
    case stashFailure
}
