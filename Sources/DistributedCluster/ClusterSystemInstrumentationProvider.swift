// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO
import NIOSSL
import ServiceDiscovery
import SWIM

import class Foundation.ProcessInfo

internal protocol ClusterSystemInstrumentationProvider {
    var actorTransportInstrumentation: (() -> InternalActorTransportInstrumentation)? { get }
    var receptionistInstrumentation: (() -> ReceptionistInstrumentation)? { get }
}
