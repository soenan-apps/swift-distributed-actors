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

import Dispatch
import NIO

// discuss naming of `InternalMessageDispatcher`

/// Contains dispatcher methods that we need internally, but don't want to
/// expose the users, because they are not safe to call from user code.
internal protocol InternalMessageDispatcher: MessageDispatcher {
    /// Gracefully shuts down the dispatcher, waiting for active execution runs
    /// to finish. Does not wait for scheduled, but not active work items to be
    /// completed.
    func shutdown()
}

// MARK: Calling ClusterThread Dispatcher

/// Use with great caution!! Hijacks the calling thread to execute the actor.
///
/// Can cause severe and bad interactions with supervision.
internal struct CallingThreadDispatcher: MessageDispatcher {
    internal var name: String {
        "callingThread:\(currentPThreadThreadID())"
    }

    @inlinable
    internal func execute(_ task: () -> Void) {
        task()
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: NIO Dispatcher only for internal use

internal struct NIOEventLoopGroupDispatcher: InternalMessageDispatcher {
    internal let group: NIO.EventLoopGroup

    internal var name: String {
        "nio:\(currentPThreadThreadID())"
    }

    internal init(_ group: EventLoopGroup) {
        self.group = group
    }

    internal func execute(_ task: @escaping () -> Void) {
        self.group.next().execute(task)
    }

    internal func shutdown() {
        self.group.shutdownGracefully(queue: DispatchQueue.global()) { _ in () }
    }
}

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: DispatchQueue Dispatcher

internal struct DispatchQueueDispatcher: MessageDispatcher {
    internal let queue: DispatchQueue

    internal var name: String {
        "dispatchQueue:\(self.queue)"
    }

    internal init(queue: DispatchQueue) {
        self.queue = queue
    }

    internal func execute(_ task: @escaping () -> Void) {
        self.queue.async {
            task()
        }
    }
}

// MessageDispatcher is going to be replaced by custom Executor types in Swift itself
/// An `Executor` is a low building block that is able to take blocks and schedule them for running
@usableFromInline
internal protocol MessageDispatcher {
    // we should make it dedicated to dispatch() rather than raw executing perhaps? This way it can take care of
    // fairness things

    var name: String { get }

    func execute(_ task: @escaping () -> Void)
}

extension FixedThreadPool: InternalMessageDispatcher {
    /// 実行中のpthreadを識別する名前。
    public var name: String {
        currentPThreadThreadID()
    }

    /// 指定した仕事をスレッドプールへ送る。
    @inlinable
    public func execute(_ task: @escaping () -> Void) {
        self.submit(task)
    }
}
