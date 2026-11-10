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

import CoreMetrics
import Logging

extension OperationLogClusterReceptionist {
    internal enum TraceLogType: CustomStringConvertible {
        case receive(from: ActorRef<Message>?)
        case push(destination: ActorRef<Message>)

        internal static var receive: Self {
            .receive(from: nil)
        }

        internal var description: String {
            switch self {
            case .receive(nil):
                return "RECV"

            case .push(let destination):
                return "PUSH(to:\(destination.id))"

            case let .receive(.some(sender)):
                return "RECV(from:\(sender.id))"
            }
        }
    }

    /// Optional "dump all messages" logging.
    ///
    /// Enabled by `Settings.traceLogLevel` or `-DSACT_TRACELOG_RECEPTIONIST`
    internal func tracelog<Payload>(
        _ context: ActorContext<Message>,
        _ type: TraceLogType,
        message: Payload,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        if let level = context.system.settings.receptionist.traceLogLevel {
            context.log.log(
                level: level,
                "[tracelog:receptionist] \(type.description): \(message)",
                file: file,
                function: function,
                line: line
            )
        }
    }

}
