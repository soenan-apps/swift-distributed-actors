import Distributed

/// リモートの呼び出し先が既に存在しないことを示す。
public struct DeadLetterError: DistributedActorSystemError, CustomStringConvertible, Hashable, Codable {
    internal enum CodingKeys: CodingKey {
        case file
        case line
        case recipient
    }

    /// 配送できなかった宛先。
    public let recipient: ClusterSystem.ActorID
    internal let file: String?
    internal let line: UInt

    public var description: String {
        if let file {
            return "\(Self.self)(recipient: \(self.recipient), location: \(file):\(self.line))"
        }
        return "\(Self.self)(\(self.recipient))"
    }

    internal init(recipient: ClusterSystem.ActorID, file: String = #fileID, line: UInt = #line) {
        self.recipient = recipient
        self.file = file
        self.line = line
    }

    /// 配送された宛先だけを復元し、送信元のソース位置は引き継がない。
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.recipient = try container.decode(ClusterSystem.ActorID.self, forKey: .recipient)
        self.file = nil
        self.line = 0
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.recipient == rhs.recipient
    }

    public func hash(into hasher: inout Hasher) {
        self.recipient.hash(into: &hasher)
    }

    /// ソース位置を含めず、宛先だけをエンコードする。
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.recipient, forKey: .recipient)
    }
}
