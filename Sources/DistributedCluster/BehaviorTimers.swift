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

import Dispatch
import Distributed
import Logging

import struct NIO.TimeAmount

@usableFromInline
internal struct Timer<Message> {
    internal let key: TimerKey
    @usableFromInline internal let message: Message?
    @usableFromInline internal let repeated: Bool
    @usableFromInline internal let generation: Int
    @usableFromInline internal let handle: Cancelable
}

@usableFromInline
internal struct TimerEvent {
    internal let key: TimerKey
    internal let generation: Int
    internal let owner: ActorID
}

/// 再利用できるタイマー識別子。システム用キーはcancelAllの通常対象に含めない。
internal struct TimerKey: Hashable, CustomStringConvertible,
    ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    private let identifier: AnyHashable
    @usableFromInline internal let isSystemTimer: Bool

    internal var description: String {
        if self.isSystemTimer {
            return "_TimerKey(\(self.identifier), isSystemTimer: \(self.isSystemTimer))"
        }
        return "_TimerKey(\(self.identifier.base))"
    }

    internal init<T: Hashable>(_ identifier: T) {
        self.init(identifier, isSystemTimer: false)
    }

    internal init<T: Hashable>(_ identifier: T, isSystemTimer: Bool) {
        self.identifier = AnyHashable(identifier)
        self.isSystemTimer = isSystemTimer
    }

    internal init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }
}

/// Actorの世代と所有者を照合して、メッセージ用タイマーを管理する。
public final class BehaviorTimers<Message: Codable> {
    @usableFromInline
    internal struct ScheduledResume<T> {
        internal let token: T
    }

    @usableFromInline internal var timerGen: Int = 0
    @usableFromInline internal let dispatchQueue: DispatchQueue = DispatchQueue.global()
    internal var installedTimers: [TimerKey: Timer<Message>] = [:]
    @usableFromInline internal unowned var context: ActorContext<Message>

    @usableFromInline internal var metadata: Logger.Metadata {
        ["tag": "timers"]
    }

    internal lazy var timerCallback: AsynchronousCallback<TimerEvent> =
        self.context.makeAsynchronousCallback { [weak context = self.context] timerEvent in
            if let context = context {
                if timerEvent.owner.path != context.path {
                    context.log.warning(
                        """
                        Received timer signal with key [\(timerEvent.key)] for different actor \
                        with path [\(context.path)]. Will ignore and continue.
                        """,
                        metadata: self.metadata
                    )
                    return
                }
                if let timer = self.installedTimers[timerEvent.key] {
                    if timer.generation != timerEvent.generation {
                        context.log.warning(
                            """
                            Received timer event for old generation [\(timerEvent.generation)], \
                            expected [\(timer.generation)]. Will ignore and continue.
                            """,
                            metadata: self.metadata
                        )
                        return
                    }
                    if let message = timer.message {
                        context.myself.tell(message)
                    }
                    if !timer.repeated {
                        self.cancel(for: timer.key)
                    }
                }
            }
        }

    internal init(context: ActorContext<Message>) {
        self.context = context
    }

    /// システム用のタイマーを残し、ユーザが開始したタイマーをすべて取り消す。
    public func cancelAll() {
        self.cancelAll(includeSystemTimers: false)
    }

    internal func cancelAll(includeSystemTimers: Bool) {
        for key in self.installedTimers.keys where includeSystemTimers || !key.isSystemTimer {
            self.cancel(for: key)
        }
    }

    /// 指定したキーのタイマーを取り消す。
    internal func cancel(for key: TimerKey) {
        if let timer = self.installedTimers.removeValue(forKey: key) {
            if context.system.settings.logging.verboseTimers {
                self.context.log.trace(
                    "Cancel timer [\(key)] with generation [\(timer.generation)]",
                    metadata: self.metadata
                )
            }
            timer.handle.cancel()
        }
    }

    internal func exists(key: TimerKey) -> Bool {
        self.installedTimers[key] != nil
    }

    internal func startSingle(key: TimerKey, message: Message, delay: Duration) {
        self.start(key: key, message: message, interval: delay, repeated: false)
    }

    internal func startPeriodic(key: TimerKey, message: Message, interval: Duration) {
        self.start(key: key, message: message, interval: interval, repeated: true)
    }

    internal func start(key: TimerKey, message: Message, interval: Duration, repeated: Bool) {
        self.cancel(for: key)
        let generation: Int = self.nextTimerGen()
        let event: TimerEvent = TimerEvent(key: key, generation: generation, owner: self.context.myself.id)
        let handle: Cancelable
        let callback: AsynchronousCallback<TimerEvent> = self.timerCallback
        if repeated {
            handle = self.dispatchQueue.schedule(initialDelay: interval, interval: interval) {
                callback.invoke(event)
            }
        } else {
            handle = self.dispatchQueue.scheduleOnce(delay: interval) {
                callback.invoke(event)
            }
        }
        if context.system.settings.logging.verboseTimers {
            self.context.log.trace("Started timer [\(key)] with generation [\(generation)]", metadata: self.metadata)
        }
        self.installedTimers[key] = Timer(
            key: key,
            message: message,
            repeated: repeated,
            generation: generation,
            handle: handle
        )
    }

    internal func nextTimerGen() -> Int {
        defer { self.timerGen += 1 }
        return self.timerGen
    }

    /// システム用キーでresume通知を予約し、監督処理の待機を再開する。
    internal func startResumeTimer<T>(key: TimerKey, delay: Duration, resumeWith token: T) {
        assert(
            key.isSystemTimer,
            "_startResumeTimer MUST ONLY be used by system internal tasks, "
                + "and keys MUST be `_` prefixed. Key was: \(key)"
        )
        self.cancel(for: key)
        let generation: Int = self.nextTimerGen()
        let handle: Cancelable = self.dispatchQueue.scheduleOnce(delay: delay) { [weak context = self.context] in
            guard let context = context else {
                return
            }
            traceLog_Supervision(
                "executing the task ::: \(context.myself)",
                file: #fileID,
                line: #line
            )
            context.myself.asAddressable.sendSystemMessage(.resume(.success(token)), file: #filePath, line: #line)
        }
        traceLog_Supervision(
            "Scheduled actor wake-up [\(key)] with generation [\(generation)], in \(delay.prettyDescription)",
            file: #fileID,
            line: #line
        )
        self.context.log.debug(
            "Scheduled actor wake-up [\(key)] with generation [\(generation)], in \(delay.prettyDescription)",
            metadata: self.metadata
        )
        self.installedTimers[key] = Timer(
            key: key,
            message: nil,
            repeated: false,
            generation: generation,
            handle: handle
        )
    }
}
