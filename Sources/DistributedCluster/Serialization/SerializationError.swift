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

import Foundation

/// シリアライズ処理の失敗とその発生箇所。
public struct SerializationError: Error, CustomStringConvertible {
    internal enum SerializationFailure {
        case alreadyDefined(hint: String, serializerID: Serialization.SerializerID)
        case emptyRepeatedField(String)
        case missingField(String, type: String)
        case missingManifest(hint: String)
        /// コーダーにアクター参照の解決コンテキストが設定されていない。
        case missingSerializationContext(Any.Type, details: String, file: String, line: UInt)
        /// シリアライザーの確保を必要としない型を示す内部制御フロー。
        case noNeedToEnsureSerializer
        case nonTransportableMessage(type: String)
        case noSerializerKeyAvailableFor(hint: String)
        case noSerializerRegisteredFor(manifest: Serialization.Manifest?, hint: String)
        case notAbleToDeserialize(hint: String)
        case notEnoughArgumentsEncoded(expected: Int, have: Int)
        case reservedSerializerID(hint: String)
        case serializationError(_: Error, file: String, line: UInt)
        case unableToCreateManifest(hint: String)
        case unableToDeserialize(hint: String)
        case unableToMakeSerializer(hint: String)
        case unableToSerialize(hint: String)
        /// 未登録または非公開の型をマニフェストから復元できない。
        case unableToSummonTypeFromManifest(Serialization.Manifest)
        case unknownEnumValue(Int)
        case wrongSerializer(hint: String)
    }

    internal class Storage {
        internal let error: SerializationFailure
        internal let file: String
        internal let line: UInt

        internal init(error: SerializationFailure, file: String, line: UInt) {
            self.error = error
            self.file = file
            self.line = line
        }
    }

    internal let underlying: Storage

    public var description: String {
        "\(Self.self)(\(self.underlying.error), at: \(self.underlying.file):\(self.underlying.line))"
    }

    internal init(_ error: SerializationFailure, file: String = #fileID, line: UInt = #line) {
        self.underlying = Storage(error: error, file: file, line: line)
    }

    /// コンテキストを欠く符号化境界のエラーを構築する。
    public static func missingSerializationContext(
        _ coder: Swift.Decoder,
        _ messageType: Any.Type,
        file: String = #filePath,
        line: UInt = #line
    ) -> Self {
        Self(
            .missingSerializationContext(
                messageType,
                details:
                    """
                    \(String(reflecting: Serialization.Context.self)) not available in \
                    \(String(reflecting: type(of: coder))).userInfo, \
                    but is necessary decode message of type: \(String(reflecting: messageType))
                    """,
                file: file,
                line: line
            )
        )
    }

    /// コンテキストを欠く符号化境界のエラーを構築する。
    public static func missingSerializationContext(
        _ coder: Swift.Encoder,
        _ message: Any,
        file: String = #filePath,
        line: UInt = #line
    ) -> Self {
        Self(
            .missingSerializationContext(
                type(of: message),
                details:
                    """
                    \(String(reflecting: Serialization.Context.self)) not available in \
                    \(String(reflecting: type(of: coder))).userInfo, \
                    but is necessary encode message: [\(message)]:\(String(reflecting: type(of: message)))
                    """,
                file: file,
                line: line
            )
        )
    }
}
