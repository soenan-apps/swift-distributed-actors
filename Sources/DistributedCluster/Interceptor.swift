// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOPosix

/// Used in combination with `Behavior.intercept` to intercept messages and signals delivered to a behavior.
open class Interceptor<Message: Codable> {
    /// メッセージとシグナルをそのまま転送する、状態を持たないinterceptorを作る。
    public init() {
        // 基底クラスには初期化する状態がない。
    }

    /// メッセージをtargetへ渡す。サブクラスは処理の前後で介入できる。
    @inlinable
    open func interceptMessage(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        message: Message
    ) throws -> Behavior<Message> {
        // Interceptors may handle only signals or only messages; the default implementation forwards both.
        try target.interpretMessage(context: context, message: message)
    }

    /// シグナルをtargetへ渡す。サブクラスは処理の前後で介入できる。
    @inlinable
    open func interceptSignal(
        target: Behavior<Message>,
        context: ActorContext<Message>,
        signal: Signal
    ) throws -> Behavior<Message> {
        // Interceptors may handle only signals or only messages; the default implementation forwards both.
        try target.interpretSignal(context: context, signal: signal)
    }

    /// 同じinterceptorとして重複排除できるかを判定する。既定では参照同一性を使う。
    @inlinable
    open func isSame(as other: Interceptor<Message>) -> Bool {
        self === other
    }
}
