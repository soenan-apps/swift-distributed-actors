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

import NIO

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: ByteBuffer extensions

extension ByteBuffer {
    /// Intended for ad-hoc debugging purposes of network data or serialized payloads.
    internal var formatHexDump: String {
        self.formatHexDump()
    }

    private static func hexDumpASCII(_ byte: UInt8) -> String {
        if (0x20...0x7F).contains(byte) {
            return "\(Character(UnicodeScalar(byte)))"
        }
        return "."
    }

    /// Intended for ad-hoc debugging purposes of network data or serialized payloads.
    internal func formatHexDump(maxBytes: Int = 80, bytesPerLine: Int = 16) -> String {
        let padding: String = String(repeating: " ", count: 4)
        func asHex(_ byte: UInt8) -> String {
            let hexadecimal: String = String(byte, radix: 16, uppercase: true)
            if byte < 16 {
                return "0\(hexadecimal)"  // poor-man's leftPad
            }
            return hexadecimal
        }

        func formatLine(_ bytes: ArraySlice<UInt8>) -> String {
            var index: Int = 0
            var hex: String = bytes.map { byte -> String in
                let space: String
                index += 1
                if index.isMultiple(of: 8) {
                    space = "  "  // double space, to separate octets
                } else {
                    space = " "
                }
                return "\(asHex(byte))\(space)"
            }.joined()
            hex += String(repeating: " ", count: bytesPerLine * 3)
            hex = String(hex.prefix(bytesPerLine * 3))

            let ascii: String = bytes.map { Self.hexDumpASCII($0) }.joined()
            return "\(padding)\(hex)  | \(ascii)"
        }
        func formatBytes(bytes: [UInt8]) -> String {
            var res: [String] = []

            var remainingBytes: ArraySlice<UInt8> = bytes[...]
            while !remainingBytes.isEmpty {
                let group: ArraySlice<UInt8> = remainingBytes.prefix(bytesPerLine)
                remainingBytes = remainingBytes.dropFirst(bytesPerLine)

                res.append(formatLine(group))
            }

            return res.joined(separator: "\n")
        }

        var buf: ByteBuffer = self
        var suffix: String = ""
        var limitMessage: String = ""
        if self.readableBytes > maxBytes, let limited = self.getSlice(at: 0, length: maxBytes) {
            limitMessage = ", shown: \(maxBytes)"
            buf = limited
            suffix = "\n\(padding)[ \(self.readableBytes - maxBytes) bytes truncated ... ]"
        }

        guard let bytes: [UInt8] = buf.readBytes(length: buf.readableBytes) else {
            preconditionFailure("Readable byte count must be available in the buffer")
        }
        return "ByteBuffer(readableBytes: \(self.readableBytes)\(limitMessage)), formatHexDump:\n"
            + formatBytes(bytes: bytes) + suffix
    }
}
