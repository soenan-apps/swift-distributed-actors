private enum OpLogEntryCodingKeys: String, CodingKey {
    case operation = "op"
    case sequenceRange = "sequenceRange"
}

extension OpLog.SequencedOp: Codable where Op: Codable {
    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<OpLogEntryCodingKeys> =
            try decoder.container(keyedBy: OpLogEntryCodingKeys.self)
        self.init(
            sequenceRange: try container.decode(OpLogSequenceRange.self, forKey: .sequenceRange),
            op: try container.decode(Op.self, forKey: .operation)
        )
    }

    internal func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<OpLogEntryCodingKeys> =
            encoder.container(keyedBy: OpLogEntryCodingKeys.self)
        try container.encode(self.sequenceRange, forKey: .sequenceRange)
        try container.encode(self.operation, forKey: .operation)
    }
}
