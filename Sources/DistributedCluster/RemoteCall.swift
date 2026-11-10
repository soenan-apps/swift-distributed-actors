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

/// Allows for configuring of remote calls by setting task-local values around a remote call being made.
///
/// ### Example: Override remote call timeouts
/// ```
/// try await RemoteCall.with(timeout: .seconds(1)) {
///     try await greeter.greet("Caroline")
/// }
/// ```
public enum RemoteCall {
    /// 現在のtaskに適用する分散呼出しの期限。
    @TaskLocal public static var timeout: Duration?

    /// 指定した期限をtask-local値として適用して呼出しを実行する。
    @discardableResult
    nonisolated(nonsending) public static func with<Response>(
        timeout: Duration,
        remoteCall: nonisolated(nonsending) () async throws -> Response
    ) async rethrows -> Response {
        try await Self.$timeout.withValue(timeout, operation: remoteCall)
    }
}
