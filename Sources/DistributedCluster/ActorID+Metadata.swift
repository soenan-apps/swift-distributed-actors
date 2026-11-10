// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Distributed
import Foundation

extension ActorID {
    /// Connects a distributed actor property to the metadata stored on its actor identity.
    @propertyWrapper
    public struct Metadata<Value: Sendable & Codable> {
        internal let keyType: Any.Type
        internal let id: String

        /// Metadata value accessed through the enclosing distributed actor.
        public var wrappedValue: Value {
            get { fatalError("called wrappedValue getter") }
            // swiftlint:disable:next unused_setter_value
            set { fatalError("called wrappedValue setter") }
        }

        /// Projection reserved for the enclosing distributed actor's metadata access.
        public var projectedValue: Value {
            get { fatalError("called projectedValue getter") }
            // swiftlint:disable:next unused_setter_value
            set { fatalError("called projectedValue setter") }
        }

        /// Binds the property wrapper to a typed actor metadata key.
        public init(_ keyPath: KeyPath<ActorMetadataKeys, ActorMetadataKey<Value>>) {
            let key: ActorMetadataKey<Value> = ActorMetadataKeys.defaultInstance[keyPath: keyPath]
            self.id = key.id
            self.keyType = type(of: key)
        }

        /// Reads or initializes the metadata entry on the enclosing actor's identity.
        public static subscript<EnclosingSelf: DistributedActor, FinalValue>(
            _enclosingInstance myself: EnclosingSelf,
            wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, FinalValue>,
            storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Self>
        ) -> Value
        where EnclosingSelf.ActorSystem == ClusterSystem, EnclosingSelf.ID == ClusterSystem.ActorID {
            get {
                let key: Self = myself[keyPath: storageKeyPath]
                guard let value = myself.id.metadata[key.id] as? Value else {
                    fatalError(
                        """
                        ActorID Metadata for key \(key.id):\(key.keyType) was not assigned initial value, \
                        assign one in the distributed actor's initializer.
                        """
                    )
                }
                return value
            }
            set {
                let metadata: ActorMetadata = myself.id.metadata
                let key: Self = myself[keyPath: storageKeyPath]
                if let value = metadata[key.id] {
                    fatalError(
                        """
                        Attempted to override ActorID Metadata for key \(key.id):\(key.keyType) \
                        which already had value: [\(value)] with new value: [\(String(describing: newValue))]
                        """
                    )
                }
                metadata[key.id] = newValue

                if key.id == ActorMetadataKeys.defaultInstance.wellKnown.id {
                    myself.actorSystem.wellKnownActorReady(myself)
                }
            }
        }
    }
}
