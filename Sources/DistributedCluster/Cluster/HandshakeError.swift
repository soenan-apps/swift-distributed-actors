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

internal enum HandshakeError: Error {
    /// An accept arrived after the handshake was no longer in progress.
    case acceptAttemptForNotInProgressHandshake(HandshakeStateMachine.CompletedState)
    /// The incoming connection did not begin with the SACT protocol's magic bytes.
    case illegalHandshakeMagic(was: UInt16, expected: UInt16)
    /// The local and remote protocol versions cannot negotiate an association.
    case incompatibleProtocolVersion(local: ClusterSystem.Version, remote: ClusterSystem.Version)
    /// The target identity has already been terminated.
    case targetAlreadyTombstone(selfNode: Cluster.Node, remoteNode: Cluster.Node)
    /// The offer addressed a different endpoint from the node accepting the connection.
    case targetHandshakeAddressMismatch(Wire.HandshakeOffer, selfNode: Cluster.Node)
    /// The target explicitly refused the handshake.
    case targetRejectedHandshake(selfNode: Cluster.Node, remoteNode: Cluster.Node, message: String)
}
