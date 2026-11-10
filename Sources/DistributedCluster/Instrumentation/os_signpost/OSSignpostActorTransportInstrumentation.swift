// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Instrumentation

#if canImport(Darwin)
import Foundation
import os.log
import os.signpost

@available(OSX 10.14, *)
@available(iOS 12.0, *)
@available(tvOS 12.0, *)
@available(watchOS 3.0, *)
internal struct OSSignpostActorTransportInstrumentation: InternalActorTransportInstrumentation {
    internal static let subsystem: StaticString = "com.apple.actors"
    internal static let category: StaticString = "Serialization"

    internal static let logTransportSerialization: OSLog = OSLog(
        subsystem: "\(Self.subsystem)",
        category: "\(Self.category)"
    )

    internal static let nameSerialization: StaticString = "Transport (Serialization)"
    internal static let nameDeserialization: StaticString = "Transport (Deserialization)"
    internal static let actorMessageSerializeStartPattern: StaticString =
        """
        serialize;\
        recipient-node:%{public}s;\
        recipient-path:%{public}s;\
        message-type:%{public}s;\
        message:%{public}s
        """
    internal static let actorMessageSerializeEndPattern: StaticString =
        """
        serialized;\
        bytes:%{public}d
        """

    internal static let actorMessageDeserializeStartPattern: StaticString =
        """
        deserialize;\
        recipient-node:%{public}s;\
        recipient-path:%{public}s;\
        bytes:%{public}d
        """
    internal static let actorMessageDeserializeEndPattern: StaticString =
        """
        deserialized;\
        message:%{public}s;\
        message-type:%{public}s
        """

    internal let signpostID: OSSignpostID

    internal init() {
        self.signpostID = OSSignpostID(
            log: Self.logTransportSerialization
        )
    }

    internal func remoteActorMessageSerializeStart(id: AnyObject, recipient: ActorPath, message: Any) {
        guard Self.logTransportSerialization.signpostsEnabled else {
            return
        }

        os_signpost(
            .begin,
            log: Self.logTransportSerialization,
            name: Self.nameSerialization,
            signpostID: .init(log: Self.logTransportSerialization, object: id),
            Self.actorMessageSerializeStartPattern,
            "todo",
            "\(recipient)",
            String(reflecting: type(of: message)),
            "\(message)"
        )
    }

    internal func remoteActorMessageSerializeEnd(id: AnyObject, bytes: Int) {
        guard Self.logTransportSerialization.signpostsEnabled else {
            return
        }

        os_signpost(
            .end,
            log: Self.logTransportSerialization,
            name: Self.nameSerialization,
            signpostID: .init(log: Self.logTransportSerialization, object: id),
            Self.actorMessageSerializeEndPattern,
            bytes
        )
    }

    internal func remoteActorMessageDeserializeStart(id: AnyObject, recipient: ActorPath, bytes: Int) {
        guard Self.logTransportSerialization.signpostsEnabled else {
            return
        }

        os_signpost(
            .begin,
            log: Self.logTransportSerialization,
            name: Self.nameDeserialization,
            signpostID: .init(log: Self.logTransportSerialization, object: id),
            Self.actorMessageDeserializeStartPattern,
            "todo",
            "\(recipient)",
            bytes
        )
    }

    internal func remoteActorMessageDeserializeEnd(id: AnyObject, message: Any?) {
        guard Self.logTransportSerialization.signpostsEnabled else {
            return
        }

        os_signpost(
            .end,
            log: Self.logTransportSerialization,
            name: Self.nameDeserialization,
            signpostID: .init(log: Self.logTransportSerialization, object: id),
            Self.actorMessageDeserializeEndPattern,
            "\(message.map { "\($0)" } ?? "<nil>")",
            "\(message.map { String(reflecting: type(of: $0)) } ?? "<unknown-type>")"
        )
    }
}

#endif
