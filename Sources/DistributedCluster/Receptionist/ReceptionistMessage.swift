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

import Logging

/// Marker protocol for all receptionist messages
///
/// The message implementations are located in `Receptionist.*`
///
/// - SeeAlso:
///     - `Receptionist.Message`
///     - `Receptionist.Lookup`
///     - `Receptionist.Register`
///     - `Receptionist.Subscribe`
/// INTERNAL API
public class ReceptionistMessage: Codable, @unchecked Sendable {}
