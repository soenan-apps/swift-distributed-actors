// SPDX-License-Identifier: Apache-2.0

/// Control object used to modify and interact with a spawned `Gossiper<Gossip, Acknowledgement>`.
internal struct GossiperControl<Gossip: Codable, Acknowledgement: Codable> {
    /// Internal FOR TESTING ONLY.
    internal let ref: GossipShell<Gossip, Acknowledgement>.Ref

    internal init(_ ref: GossipShell<Gossip, Acknowledgement>.Ref) {
        self.ref = ref
    }

    /// Introduce a peer to the gossip group.
    ///
    /// This method is fairly manual and error prone and as such internal only for the time being.
    /// Please use the receptionist based peer discovery instead.
    internal func introduce(peer: GossipShell<Gossip, Acknowledgement>.Ref) {
        self.ref.tell(.introducePeer(peer))
    }

    internal func update(_ identifier: GossipIdentifier, payload: Gossip) {
        self.ref.tell(.updatePayload(identifier: identifier, payload))
    }

    internal func remove(_ identifier: GossipIdentifier) {
        self.ref.tell(.removePayload(identifier: identifier))
    }

    /// Side channel messages which may be piped into specific gossip logics.
    internal func sideChannelTell(_ identifier: GossipIdentifier, message: Any) {
        self.ref.tell(.sideChannelMessage(identifier: identifier, message))
    }
}
