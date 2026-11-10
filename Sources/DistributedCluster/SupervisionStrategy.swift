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

/// Supervision strategies are a way to select and configure pre-defined supervisors.
///
/// **Supervision results in stopping or restarting**
///
/// Most of the following discussion focuses on the `.restart` strategy and its alternative versions and semantics.
/// This is because the only other strategy is `stop`, which is self explanatory: it stops the actor upon any
/// encountered failure.
///
/// **Understanding the failure time period**
///
/// The following visualization may be useful in understanding failure periods and their meaning to the "intensity"
/// of how many restarts are allowed within a failure period:
///
/// ```
/// Assuming supervision with: .restart(atMost: 2, within: .seconds(10))
///
///      fail-per-1  fail-per-2                    failure-period-3
/// TFP: 0123456789  0123456789                       0123456789
///     [x        x][x         ][... no failures ...][x   x  x!!]
///      ^        ^  ^                                ^      ^
/// |        |  |                                |      \ and whenever we hit a 3rd failure within it, we escalate
/// (do not restart, and the actor is stopped)
///      |        |  |                                \ any new failure after a while causes a new failure period
/// |        |  \ another, 3rd in total, failure happens; however it is the beginning of a new failure period; we
/// allow the restart
///      |        \ another failure happens before the end of the period, atMost: 2, so we perform the restart
///      \- a failure begins a failure period of 10 seconds
/// ```
///
/// - Warning:
/// While it is possible to omit the `within` parameter, it has a specific effect which may not often be useful:
/// a `restart` supervision directive without a `within` parameter set effectively means that a given actor is
/// allowed to restart
/// `atMost` times _in total_ (in its entire lifetime). This rarely is a behavior one would desire, however it may
/// sometimes come in handy.
///
/// - SeeAlso: Erlang OTP [Maximum Restart Intensity][restart-intensity].
///
/// [restart-intensity]: http://erlang.org/doc/design_principles/sup_princ.html#maximum-restart-intensity
///
/// **Restarting with Backoff**
///
/// It is possible to `.restart` a backoff strategy before completing a restart. In this case the passed in
/// `SupervisionStrategy`
/// is invoked and the returned `Duration` is used to suspend the actor for this amount of time, before completing
/// the restart,
/// canonicalizing any `.setup` or similar top-level behaviors and continuing to process messages.
///
/// The following diagram explains how backoff interplays with the lifecycle signals sent to the actor upon a restart,
/// as the prepare (`R`) and complete (`S`) signals of a restart would then occur in different points in time.
///
/// ```
/// Actor: [S     x]R ~~~~~~~[S      x]R~~~~~~~~~[S   ...]
///         ^     ^ ^ ^^^^^^^ ^
/// .setup    | |    |    \- Complete the restart; If present, run any .setup and other nested behaviors, continue
/// running as usual.
///               | |    \- Backoff time before completing the restart, if backoff strategy is set and returns a value.
/// | \- Signals.PreRestart is interpreted by the existing Behavior (in its .onSignal handler, if present)
///               \- "Letting it Crash!"
/// ```
///
/// Backoffs are tremendously useful in building resilient retrying systems, as they allow the avoidance of
/// thundering situations,
/// in case a fault caused multiple actors to fail for the same reason (e.g. the failure of a shared resource).
internal enum SupervisionStrategy {
    /// WARNING: Purposefully ESCALATES the failure to the parent of the spawned actor, even if it has not
    /// watched the child.
    ///
    /// This allows for constructing "fail the parent" even if the parent is not under our control.
    /// This method should not be over used, as normally the parent should decide by itself if it wants to stop
    /// or spawn a replacement child or something else, however sometimes it is useful to allow providers of props
    /// to configure a parent to be torn down when a specific child dies. E.g. when providing workers to a pool,
    /// and we want to enforce the pool dying if only a single child (or a special one) terminates.
    ///
    /// ### Escalating to guardians
    /// Root guardians, such as `/user` or `/system` take care of spawning children when `system.spawn` is invoked.
    /// These guardians normally do not care for the termination of their children, as the `stop` supervision strategy
    /// instructs them to. By spawning a top-level actor, e.g. under the `/user`-guardian and passing in the `.escalate`
    /// strategy, it is possible to escalate failures to the guardians, which in turn will cause the system to
    /// terminate.
    ///
    /// This strategy is useful whenever the failure of some specific actor should be considered "fatal to the
    /// actor system",
    /// yet we still want to perform a graceful shutdown, rather than an abrupt one (e.g. by calling `exit()`).
    case escalate
    /// The restart supervision strategy allowing the supervised actor to be restarted `atMost` times `within`
    /// a time period.
    /// In addition, each subsequent restart _may_ be performed after a certain backoff.
    ///
    /// - SeeAlso: The top level `SupervisionStrategy` documentation explores semantics of supervision in more depth.
    ///
    /// **Associated Values**
    /// - `atMost` number of attempts allowed restarts within a single failure period (defined by the `within`
    /// parameter. MUST be > 0).
    /// - `within` amount of time within which the `atMost` failures are allowed to happen. This defines the so
    /// called "failure period",
    /// which runs from the first failure encountered for `within` time, and if more than `atMost` failures
    /// happen in this time amount then
    ///     no restart is performed and the failure is escalated (and the actor terminates in the process).
    /// - `backoff` strategy to be used for suspending the failed actor for a given (backoff) amount of time
    /// before completing the restart.
    /// The actor's mailbox remains untouched by default, and it would continue processing it from where it
    /// left off before the crash;
    /// the message which caused a failure is NOT processed again. For retrying processing of such higher level
    /// mechanisms should be used.
    case restart(atMost: Int, within: Duration?, backoff: BackoffStrategy?)
    /// Default supervision strategy applied to all actors, unless a different one is selected in their `Props`.
    ///
    /// Semantically equivalent to not applying any supervision strategy at all, since not applying a strategy
    /// also means that upon encountering a failure the given actor is terminated and all of its watchers are
    /// terminated.
    ///
    /// - SeeAlso: `DeathWatch` for discussion about how to be notified about an actor stopping / failing.
    case stop
    /// Simplified version of `SupervisionStrategy.restart(atMost:within:backoff:)`.
    ///
    /// - SeeAlso: The top level `SupervisionStrategy` documentation explores semantics of supervision in more depth.
    ///
    /// **Providing a `within` time period**
    ///
    /// This version is generally useful for long running actors, which may experience periodic failures,
    /// during which time they
    /// should attempt to restart as quickly as possible (without backoff), yet if recovery is not possible and
    /// the actor keeps failing
    /// within a designated time amount, it should escalate the failure.
    ///
    /// **Empty `within` failure time period**
    ///
    /// It is possible to pass in `nil` as time period explicitly, which effectively disables the time period.
    /// This is only useful for temporary actors which should terminate after they have completed a specific task,
    /// and the `atMost` allowed failures count is related to this task.
    ///
    /// For example `.restart(atMost: 2)` could be well suited for an actor that should try downloading a web page,
    /// but if it fails twice at the task -- regardless how long it took to fetch/fail, it should be restarted.
    ///
    /// **Associated Values**
    /// - `atMost` number of attempts allowed restarts within a single failure period (defined by the `within`
    /// parameter. MUST be > 0).
    /// - `within` amount of time within which the `atMost` failures are allowed to happen. This defines the so
    /// called "failure period",
    /// which runs from the first failure encountered for `within` time, and if more than `atMost` failures
    /// happen in this time amount then
    ///     no restart is performed and the failure is escalated (and the actor terminates in the process).
    internal static func restart(atMost: Int, within: Duration?) -> Self {
        .restart(atMost: atMost, within: within, backoff: nil)
    }
}
