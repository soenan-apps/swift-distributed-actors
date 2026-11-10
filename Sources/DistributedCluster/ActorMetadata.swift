// Copyright (c) 2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Dispatch
import Distributed

/// ActorIDに付随するタグを保持する。読み書きは内部のロックで同期する。
@dynamicMemberLookup
public final class ActorMetadata: CustomStringConvertible, CustomDebugStringConvertible {
    internal let lock: DispatchSemaphore = DispatchSemaphore(value: 1)
    private var storage: [String: Sendable & Codable] = [:]

    /// 保存しているタグの数。
    public var count: Int {
        self.lock.wait()
        defer { lock.signal() }
        return self.storage.count
    }

    /// タグが一つも保存されていないかどうか。
    public var isEmpty: Bool {
        self.lock.wait()
        defer { lock.signal() }
        return self.storage.isEmpty
    }

    public var description: String {
        self.lock.wait()
        let snapshot: [String: Sendable & Codable] = self.storage
        self.lock.signal()
        return "\(snapshot)"
    }

    public var debugDescription: String {
        self.lock.wait()
        let snapshot: [String: Sendable & Codable] = self.storage
        self.lock.signal()
        return "\(Self.self)(\(snapshot))"
    }

    /// 空のmetadataを作る。
    public init() {
        // 初期状態のstorageは空。
    }

    /// 指定したキーを削除し、保存されていた値を返す。
    public func remove<Value: Sendable & Codable>(forKey key: ActorMetadataKeys.Key<Value>) -> Value? {
        self.lock.wait()
        defer { lock.signal() }
        guard let value = self.storage.removeValue(forKey: key.id) else {
            return nil
        }
        return value as? Value
    }

    internal func copy() -> ActorMetadata {
        self.lock.wait()
        defer { lock.signal() }
        let metadataCopy: ActorMetadata = ActorMetadata()
        metadataCopy.storage = self.storage
        return metadataCopy
    }

    internal func clear() {
        self.lock.wait()
        defer { lock.signal() }
        self.storage = [:]
    }

    /// 型付きkey pathで値を読む。既存のキーに値を上書きすることはできない。
    public subscript<Value>(
        dynamicMember dynamicMember: KeyPath<ActorMetadataKeys, ActorMetadataKeys.Key<Value>>
    ) -> Value? {
        get {
            self.lock.wait()
            defer { lock.signal() }
            let key: ActorMetadataKey<Value> = ActorMetadataKeys.defaultInstance[keyPath: dynamicMember]
            guard let value = self.storage[key.id] else {
                return nil
            }
            return value as? Value
        }
        set {
            self.lock.wait()
            defer { lock.signal() }
            let key: ActorMetadataKey<Value> = ActorMetadataKeys.defaultInstance[keyPath: dynamicMember]
            if let existing = self.storage[key.id] {
                fatalError(
                    """
                    Existing ActorID metadata, cannot be replaced. Was: [\(existing)], \
                    newValue: [\(optional: newValue)]
                    """
                )
            }
            self.storage[key.id] = newValue
        }
    }

    internal subscript(_ id: String) -> (any Sendable & Codable)? {
        get {
            self.lock.wait()
            defer { lock.signal() }
            return self.storage[id]
        }
        set {
            self.lock.wait()
            defer { lock.signal() }
            if let existing = self.storage[id] {
                fatalError(
                    """
                    Existing ActorID [\(id)] metadata, cannot be replaced. Was: [\(existing)], \
                    newValue: [\(optional: newValue)]
                    """
                )
            }
            self.storage[id] = newValue
        }
    }
}
