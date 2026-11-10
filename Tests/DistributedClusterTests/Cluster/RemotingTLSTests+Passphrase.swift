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
import NIOSSL
import XCTest

@testable import DistributedCluster

extension RemotingTLSTests {
    internal func test_boundServer_shouldAcceptAssociateWithSSLEnabledAndCorrectPassphrase() async throws {
        let privateKey: NIOSSLPrivateKey = try NIOSSLPrivateKey(
            bytes: Array(self.passwordProtectedKey.utf8),
            format: .pem,
            passphraseCallback: { setter in setter(Array("test".utf8)) }
        )
        let testCertificate: NIOSSLCertificate =
            try NIOSSLCertificate(bytes: [UInt8](passordProtectedCert.utf8), format: .pem)
        let testCertificateSource: NIOSSLCertificateSource = .certificate(testCertificate)
        let testKey: NIOSSLPrivateKeySource = .privateKey(privateKey)
        let local: ClusterSystem = await setUpNode("local") { settings in
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
