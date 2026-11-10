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

import DistributedActorsTestKit
import Foundation
import NIOSSL
import XCTest

@testable import DistributedCluster

extension RemotingTLSTests {
    internal func test_boundServer_shouldAcceptAssociateWithSSLEnabled() async throws {
        let testCertificate1: NIOSSLCertificate = try NIOSSLCertificate(bytes: [UInt8](testCert1.utf8), format: .pem)
        let testCertificateSource1: NIOSSLCertificateSource = .certificate(testCertificate1)
        let testKeySource1: NIOSSLPrivateKeySource =
            .privateKey(try NIOSSLPrivateKey(bytes: [UInt8](testKey1.utf8), format: .pem))

        let testCertificate2: NIOSSLCertificate = try NIOSSLCertificate(bytes: [UInt8](testCert2.utf8), format: .pem)
        let testCertificateSource2: NIOSSLCertificateSource = .certificate(testCertificate2)
        let testKeySource2: NIOSSLPrivateKeySource =
            .privateKey(try NIOSSLPrivateKey(bytes: [UInt8](testKey2.utf8), format: .pem))

        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.endpoint.host = "localhost"
            settings.tls = TLSConfiguration.makeServerConfiguration(
                certificateChain: [testCertificateSource1],
                privateKey: testKeySource1
                    //                    ,
                    //                certificateVerification: .fullVerification,
                    //                trustRoots: .certificates([testCertificate2])
            )
            settings.tls?.certificateVerification = .fullVerification
            settings.tls?.trustRoots = .certificates([testCertificate2])
        }

        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.endpoint.host = "localhost"
            settings.tls = TLSConfiguration.makeServerConfiguration(
                certificateChain: [testCertificateSource2],
                privateKey: testKeySource2
                    //                    ,
                    //                certificateVerification: .fullVerification,
                    //                trustRoots: .certificates([testCertificate1])
            )
            settings.tls?.certificateVerification = .fullVerification
            settings.tls?.trustRoots = .certificates([testCertificate1])
        }

        local.cluster.join(endpoint: remote.cluster.node.endpoint)

        try assertAssociated(local, withExactly: remote.settings.bindNode)
    }

    internal func ignore_boundServer_shouldFailWithSSLEnabledOnHostnameVerificationWithIP() async throws {
        let testCertificate: NIOSSLCertificate = try NIOSSLCertificate(bytes: [UInt8](testCert1.utf8), format: .pem)
        let testCertificateSource: NIOSSLCertificateSource = .certificate(testCertificate)
        let testKey: NIOSSLPrivateKeySource =
            .privateKey(try NIOSSLPrivateKey(bytes: [UInt8](testKey1.utf8), format: .pem))

        let local: ClusterSystem = await self.setUpNode("local") { settings in
            settings.endpoint.host = "127.0.0.1"
            settings.tls = TLSConfiguration.makeServerConfiguration(
                certificateChain: [testCertificateSource],
                privateKey: testKey
                    //                    ,
                    //                certificateVerification: .fullVerification,
                    //                trustRoots: .certificates([testCertificate])
            )
            settings.tls?.certificateVerification = .fullVerification
            settings.tls?.trustRoots = .certificates([testCertificate])
        }

        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.endpoint.host = "127.0.0.1"
            settings.tls = TLSConfiguration.makeServerConfiguration(
                certificateChain: [testCertificateSource],
                privateKey: testKey
                    //                    ,
                    //                certificateVerification: .fullVerification,
                    //                trustRoots: .certificates([testCertificate])
            )
            settings.tls?.certificateVerification = .fullVerification
            settings.tls?.trustRoots = .certificates([testCertificate])
        }

        let testKit: ActorTestKit = ActorTestKit(local)

        local.cluster.join(endpoint: remote.cluster.node.endpoint)

        sleep(2)

        do {
            let pSystem: ActorTestProbe<Set<Cluster.Node>> = testKit.makeTestProbe(expecting: Set<Cluster.Node>.self)
            local.cluster.ref.tell(.query(.associatedNodes(pSystem.ref)))
            remote.cluster.ref.tell(.query(.associatedNodes(pSystem.ref)))
            let associatedNodes: Set<Cluster.Node> = try pSystem.expectMessage()
            associatedNodes.shouldBeEmpty()  // means we have not associated to _someone_
        }

        do {
            let pRemote: ActorTestProbe<Set<Cluster.Node>> = testKit.makeTestProbe(expecting: Set<Cluster.Node>.self)
            local.cluster.ref.tell(
                .query(.associatedNodes(pRemote.ref))
            )  // FIXME: We need to get the Accept back and act on it on the origin side
            remote.cluster.ref.tell(.query(.associatedNodes(pRemote.ref)))
            let associatedNodes: Set<Cluster.Node> = try pRemote.expectMessage()
            associatedNodes.shouldBeEmpty()  // means we have not associated to _someone_
        }
    }

    internal func test_boundServer_shouldAcceptAssociateWithSSLEnabledOnNoHostnameVerificationWithIP() async throws {
        let testCertificate: NIOSSLCertificate = try NIOSSLCertificate(bytes: [UInt8](testCert1.utf8), format: .pem)
        let testCertificateSource: NIOSSLCertificateSource = .certificate(testCertificate)
        let testKey: NIOSSLPrivateKeySource =
            .privateKey(try NIOSSLPrivateKey(bytes: [UInt8](testKey1.utf8), format: .pem))
        let local: ClusterSystem = await setUpNode("local") { settings in
            settings.endpoint.host = "localhost"
            settings.tls = TLSConfiguration.makeServerConfiguration(
                certificateChain: [testCertificateSource],
                privateKey: testKey
                    //                    ,
                    //                certificateVerification: .fullVerification,
                    //                trustRoots: .certificates([testCertificate])
            )
            settings.tls?.certificateVerification = .noHostnameVerification
            settings.tls?.trustRoots = .certificates([testCertificate])
        }

        let remote: ClusterSystem = await setUpNode("remote") { settings in
            settings.endpoint.host = "localhost"
            settings.tls = TLSConfiguration.makeServerConfiguration(
                certificateChain: [testCertificateSource],
                privateKey: testKey
                    //                    ,
                    //                certificateVerification: .fullVerification,
                    //                trustRoots: .certificates([testCertificate])
            )
            settings.tls?.certificateVerification = .noHostnameVerification
            settings.tls?.trustRoots = .certificates([testCertificate])
        }

        local.cluster.join(endpoint: remote.cluster.node.endpoint)

        try assertAssociated(local, withExactly: remote.settings.bindNode)
    }
}
