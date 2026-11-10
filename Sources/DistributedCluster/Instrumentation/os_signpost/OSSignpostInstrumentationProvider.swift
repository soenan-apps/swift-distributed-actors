// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

#if canImport(Darwin)
/// Provider of Instrumentation instances which use `os_signpost`.
internal struct OSSignpostInstrumentationProvider: ClusterSystemInstrumentationProvider {

    internal var actorTransportInstrumentation: (() -> InternalActorTransportInstrumentation)? {
        if #available(OSX 10.14, iOS 12.0, *) {
            return OSSignpostActorTransportInstrumentation.init
        } else {
            return nil
        }
    }

    internal var receptionistInstrumentation: (() -> ReceptionistInstrumentation)? {
        if #available(OSX 10.14, iOS 12.0, *) {
            return OSSignpostReceptionistInstrumentation.init
        } else {
            return nil
        }
    }
}
#endif
