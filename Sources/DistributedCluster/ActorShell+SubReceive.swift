// Copyright (c) 2018-2022 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
// SPDX-License-Identifier: Apache-2.0

import Logging
import NIO

extension ActorShell {
    /// Registers or replaces a sub-receive adapter in this shell's actor-isolated state.
    internal func registerSubReceive<SubMessage>(
        _ id: SubReceiveId<SubMessage>,
        _ subType: SubMessage.Type,
        _ closure: @escaping (SubMessage) throws -> Void
    ) -> ActorRef<SubMessage>
    where SubMessage: Codable {
        do {
            let wrappedClosure: (SubMessageCarry) throws -> Behavior<Message> = { carry in
                guard let message = carry.message as? SubMessage else {
                    self.log.warning("""
                        Received message [\(carry.message)] of type \
                        [\(String(reflecting: type(of: carry.message)))] for identifier \
                        [\(carry.identifier)] and address [\(carry.subReceiveAddress)]
                        """)
                    return .same  // make .drop once implemented
                }

                try closure(message)
                return .same
            }

            let identifier: AnySubReceiveId = AnySubReceiveId(id)
            if let (_, existingRef) = self.subReceives[identifier] {
                self.subReceives[identifier] = (wrappedClosure, existingRef)
                guard let adapter = existingRef as? SubReceiveAdapter<SubMessage, Message> else {
                    fatalError("""
                        Existing ref for sub receive id [\(id)] has unexpected type \
                        [\(String(reflecting: type(of: existingRef)))], expected \
                        [\(String(reflecting: SubMessage.self))]
                        """)
                }
                return .init(.adapter(adapter))
            }

            let naming: ActorNaming = ActorNaming(unchecked: .prefixed(prefix: "$sub-\(id.id)", suffixScheme: .letters))
            let spawnedName: String = naming.makeName(&self.namingContext)
            let adaptedAddress: ActorID = try self.id.makeChildID(name: spawnedName, incarnation: .random())
            let ref: SubReceiveAdapter<SubMessage, Message> = SubReceiveAdapter(
                SubMessage.self, owner: self.myself, id: adaptedAddress, identifier: identifier
            )

            self.childActors.insert(ref)  // separate adapters collection?
            self.subReceives[identifier] = (wrappedClosure, ref)
            return .init(.adapter(ref))
        } catch {
            fatalError(
                """
                Failed while creating a sub receive with id [\(id.id)] and type [\(subType)]. This should \
                never happen, since sub receives have unique names \
                generated for them using sequential names. Maybe `ActorContext.subReceive` was accessed \
                concurrently (which is unsafe!)? \
                Error: \(error)
                """
            )
        }
    }
}
