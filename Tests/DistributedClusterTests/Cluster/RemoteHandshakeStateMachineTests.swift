// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import DistributedActorsTestKit
import Foundation
import Logging
import NIO
import XCTest

@testable import DistributedCluster

internal final class RemoteHandshakeStateMachineTests: XCTestCase {
    private typealias HSM = HandshakeStateMachine

    private let systemName: String = "RemoteHandshakeStateMachineTests"

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Happy path handshakes

    internal func test_handshake_happyPath() throws {
        let serverKernel: ClusterShellState = ClusterShellState.makeTestMock(side: .server, configureSettings: nil)
        let serverAddress: Cluster.Node = serverKernel.selfNode

        let clientKernel: ClusterShellState = ClusterShellState.makeTestMock(side: .client) { settings in
            settings.endpoint.port = 2_222
        }

        // client
        let clientInitiated: HSM.InitiatedState =
            HSM.InitiatedState(
                settings: clientKernel.settings,
                localNode: clientKernel.selfNode,
                connectTo: serverAddress.endpoint
            )
        let offer: Wire.HandshakeOffer = clientInitiated.makeOffer()

        // server
        let received: HSM.HandshakeOfferReceivedState =
            HSM.HandshakeOfferReceivedState(state: serverKernel, offer: offer)

        let serverCompleted: HSM.CompletedState
        switch received.negotiate() {
        case .acceptAndAssociate(let completed):
            serverCompleted = completed

        case .rejectHandshake:
            throw shouldNotHappen("Must not reject the handshake")
        }

        // client
        let clientCompleted: HSM.CompletedState =
            HSM.CompletedState(fromInitiated: clientInitiated, remoteNode: serverAddress)

        // then

        serverCompleted.localNode.shouldEqual(serverKernel.selfNode)
        serverCompleted.remoteNode.shouldEqual(clientKernel.selfNode)

        clientCompleted.remoteNode.shouldEqual(serverKernel.selfNode)
        clientCompleted.localNode.shouldEqual(clientKernel.selfNode)
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Version negotiation

    internal func test_negotiate_server_shouldAcceptClient_newerPatch() throws {
        let serverKernel: ClusterShellState = ClusterShellState.makeTestMock(side: .server, configureSettings: nil)
        let serverAddress: Cluster.Node = serverKernel.selfNode

        let clientKernel: ClusterShellState = ClusterShellState.makeTestMock(side: .client) { settings in
            settings.endpoint.port = 2_222
            settings.protocolVersion.patch += 1
        }

        let clientInitiated: HSM.InitiatedState =
            HSM.InitiatedState(
                settings: clientKernel.settings,
                localNode: clientKernel.selfNode,
                connectTo: serverAddress.endpoint
            )
        let offer: Wire.HandshakeOffer = clientInitiated.makeOffer()

        // server
        let received: HSM.HandshakeOfferReceivedState =
            HSM.HandshakeOfferReceivedState(state: serverKernel, offer: offer)

        // then

        switch received.negotiate() {
        case .acceptAndAssociate:
            ()

        case .rejectHandshake:
            throw shouldNotHappen("Must not reject the handshake")
        }
    }

    internal func test_negotiate_server_shouldRejectClient_newerMajor() throws {
        let serverKernel: ClusterShellState = ClusterShellState.makeTestMock(side: .server, configureSettings: nil)
        let serverAddress: Cluster.Node = serverKernel.selfNode

        let clientKernel: ClusterShellState = ClusterShellState.makeTestMock(side: .client) { settings in
            settings.endpoint.port = 2_222
            settings.protocolVersion.major += 1
        }

        let clientInitiated: HSM.InitiatedState =
            HSM.InitiatedState(
                settings: clientKernel.settings,
                localNode: clientKernel.selfNode,
                connectTo: serverAddress.endpoint
            )
        let offer: Wire.HandshakeOffer = clientInitiated.makeOffer()

        // server
        let received: HSM.HandshakeOfferReceivedState =
            HSM.HandshakeOfferReceivedState(state: serverKernel, offer: offer)

        // then

        let error: Error
        switch received.negotiate() {
        case .acceptAndAssociate(let completed):
            throw shouldNotHappen("Must not accept handshake from such much more new-er node; \(completed)")

        case .rejectHandshake(let rejected):
            error = rejected.error
        }

        "\(error)".shouldEqual(
            "incompatibleProtocolVersion(local: Version(1.0.0, reserved:0), remote: Version(2.0.0, reserved:0))"
        )
    }

    // ==== ------------------------------------------------------------------------------------------------------------
    // MARK: Handshake timeout causing retries

    internal func test_onTimeout_shouldReturnNewHandshakeOffersMultipleTimes() throws {
        let serverKernel: ClusterShellState = ClusterShellState.makeTestMock(side: .server, configureSettings: nil)
        let serverAddress: Cluster.Node = serverKernel.selfNode

        let clientKernel: ClusterShellState = ClusterShellState.makeTestMock(side: .client) { settings in
            settings.endpoint.port = 8_228
        }

        // client
        var clientInitiated: HSM.InitiatedState =
            HSM.InitiatedState(
                settings: clientKernel.settings,
                localNode: clientKernel.selfNode,
                connectTo: serverAddress.endpoint
            )

        guard case .scheduleRetryHandshake = clientInitiated.onHandshakeTimeout() else {
            throw shouldNotHappen("Expected retry attempt after handshake timeout")
        }
        guard case .scheduleRetryHandshake = clientInitiated.onHandshakeTimeout() else {
            throw shouldNotHappen("Expected retry attempt after handshake timeout")
        }

        guard case .scheduleRetryHandshake = clientInitiated.onConnectionError(TestError("Boom!")) else {
            throw shouldNotHappen("Expected retry attempt after handshake timeout")
        }
    }
}
