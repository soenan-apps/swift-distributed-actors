// ===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// ===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

import Distributed
import DistributedCluster
import NIOCore
import NIOFoundationCompat
import NIOPosix

import class Foundation.FileHandle
import class Foundation.Pipe

internal struct ProgramOutput: Sendable {
    internal let logs: [String]
    internal var expectedExit: Bool = false

    internal init(logs: [String]) {
        self.logs = logs
    }

    internal init(logs: [String], expectedExit: Bool) {
        self.logs = logs
        self.expectedExit = expectedExit
    }
}

private final class GrepHandler: ChannelInboundHandler {
    typealias InboundIn = String

    private let promise: EventLoopPromise<ProgramOutput>

    let nodeName: String
    var logs: [String] = []
    var programLogReceiver: (any ProgramLogReceiver)?

    init(
        nodeName: String,
        promise: EventLoopPromise<ProgramOutput>,
        programLogRecipient: ProgramLogReceiver?
    ) {
        self.nodeName = nodeName
        self.promise = promise
        self.programLogReceiver = programLogRecipient
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.promise.fail(error)
        context.close(promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let line: String = self.unwrapInboundIn(data)

        if let receiver = self.programLogReceiver {
            // send to receiver
            let outputPromise: EventLoopPromise<ProgramOutput> = self.promise
            Task {
                do {
                    try await receiver.logProgramOutput(line: line)
                } catch {
                    outputPromise.fail(error)
                }
            }
        } else {
            // accumulate locally
            logs.append(line)
        }

        // Detect crashes
        let lowercaseLine: String = line.lowercased()
        if lowercaseLine.contains("fatal error")
            || lowercaseLine.contains("precondition failed")
            || lowercaseLine.contains("assertion failed")
        {
            if line.contains("MULTI-NODE-EXPECTED-EXIT") {
                self.promise.succeed(.init(logs: logs, expectedExit: true))
                context.close(promise: nil)
                return
            }
            self.promise.fail(MultiNodeProgramError(message: line, completeOutput: self.logs))
            self.logs = []
            context.close(promise: nil)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if case .some(.inputClosed) = event as? ChannelEvent {
            self.promise.succeed(.init(logs: self.logs))
            context.close(promise: nil)
        }
    }

    func handlerRemoved(context _: ChannelHandlerContext) {
        self.promise.fail(ChannelError.alreadyClosed)
    }
}

internal protocol ProgramLogReceiver {
    func logProgramOutput(line: String) async throws
}

internal distributed actor DistributedProgramLogReceiver: ProgramLogReceiver {
    internal typealias ActorSystem = ClusterSystem

    internal var logs: [String] = []

    internal distributed func logProgramOutput(line: String) {
        self.logs.append(line)
    }

    internal func dumpOutput() {
        for line in self.logs {
            print("[dump] \(line)")
        }
    }
}

internal struct MultiNodeProgramError: Error, CustomStringConvertible {
    internal let message: String
    internal let completeOutput: [String]
    internal var description: String {
        "\(Self.self)(\(self.message), completeOutput: <\(self.completeOutput.count) lines>)"
    }
}

private struct NewlineFramer: ByteToMessageDecoder {
    typealias InboundOut = String

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) -> DecodingState {
        if let firstNewline = buffer.readableBytesView.firstIndex(of: UInt8(ascii: "\n")) {
            let length: Int = firstNewline - buffer.readerIndex + 1
            guard let line = buffer.readString(length: length) else {
                preconditionFailure("The newline frame must be within readable bytes")
            }
            context.fireChannelRead(self.wrapInboundOut(String(line.dropLast())))
            return .continue
        }
        return .needMoreData
    }
}

internal struct OutputGrepper {
    internal var result: EventLoopFuture<ProgramOutput>
    internal var processOutputPipe: FileHandle

    internal static func make(
        nodeName: String,
        group: EventLoopGroup,
        programLogRecipient: (any ProgramLogReceiver)? = nil
    ) -> Self {
        let processToChannel: Pipe = Pipe()
        let deadPipe: Pipe = Pipe()  // just so we have an output...

        let eventLoop: any EventLoop = group.next()
        let outputPromise: EventLoopPromise<ProgramOutput> = eventLoop.makePromise(of: ProgramOutput.self)

        // We gotta `dup` everything because Pipe is bad and closes file descriptors on `deinit` :(
        let channelFuture: EventLoopFuture<any Channel> = NIOPipeBootstrap(group: group)
            .channelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandlers(
                        [
                            ByteToMessageHandler(NewlineFramer()),
                            GrepHandler(
                                nodeName: nodeName,
                                promise: outputPromise,
                                programLogRecipient: programLogRecipient
                            ),
                        ]
                    )
                }
            }
            .takingOwnershipOfDescriptors(
                input: dup(processToChannel.fileHandleForReading.fileDescriptor),
                output: dup(deadPipe.fileHandleForWriting.fileDescriptor)
            )
        let outputHandle: FileHandle = FileHandle(
            fileDescriptor: dup(processToChannel.fileHandleForWriting.fileDescriptor),
            closeOnDealloc: true
        )
        processToChannel.fileHandleForReading.closeFile()
        processToChannel.fileHandleForWriting.closeFile()
        deadPipe.fileHandleForReading.closeFile()
        deadPipe.fileHandleForWriting.closeFile()
        channelFuture.cascadeFailure(to: outputPromise)
        return Self(
            result: outputPromise.futureResult,
            processOutputPipe: outputHandle
        )
    }
}
