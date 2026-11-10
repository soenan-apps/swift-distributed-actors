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

import DistributedCluster
import NIOSSL
import XCTest

@testable import DistributedActorsTestKit

internal final class ClusteringDocExamples: XCTestCase {
    private func example_config_tls() async throws {
        // tag::config_tls[]
        let certificates: [NIOSSLCertificateSource] = try NIOSSLCertificate
            .fromPEMFile("/path/to/certificate.pem")
            .map { NIOSSLCertificateSource.certificate($0) }
        let system: ClusterSystem = await ClusterSystem("TestSystem") { settings in
            // ...
            settings.tls = TLSConfiguration.makeServerConfiguration(  // <1>
                certificateChain: certificates,  // <2>
                privateKey: .file("/path/to/private-key.pem")  // , // <3>
                //                certificateVerification: .fullVerification, // <4>
                //                trustRoots: .file("/path/to/certificateChain.pem")
            )  // <5>
            settings.tls?.certificateVerification = .fullVerification
            settings.tls?.trustRoots = .file("/path/to/certificateChain.pem")
        }
        // end::config_tls[]

        try await system.shutdown().wait()
    }

    private func example_config_tls_passphrase() async throws {
        // tag::config_tls_passphrase[]
        let system: ClusterSystem = await ClusterSystem("TestSystem") { settings in
            // ...
            settings.tlsPassphraseCallback = { setter in
                setter([UInt8]("password".utf8))
            }
        }
        // end::config_tls_passphrase[]

        try await system.shutdown().wait()
    }
}
