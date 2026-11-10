internal enum OpLogSequenceRange: Codable, Equatable {
    case inclusiveRange(UInt64, UInt64)
    case single(UInt64)

    private enum DiscriminatorKeys: String, Codable {
        case inclusiveRange = "inclusiveRange"
        case single = "single"
    }

    private enum CodingKeys: String, CodingKey {
        case discriminator = "_case"
        case inclusiveRangeFrom = "inclusiveRange_from"
        case inclusiveRangeTo = "inclusiveRange_to"
        case singleValue = "single_value"
    }

    internal var max: UInt64 {
        switch self {
        case .single(let sequenceNumber):
            return sequenceNumber

        case .inclusiveRange(_, let upperBound):
            return upperBound
        }
    }

    internal var min: UInt64 {
        switch self {
        case .single(let sequenceNumber):
            return sequenceNumber

        case .inclusiveRange(let lowerBound, _):
            return lowerBound
        }
    }

    internal init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: .discriminator) {
        case .single:
            self = .single(try container.decode(UInt64.self, forKey: .singleValue))

        case .inclusiveRange:
            let lowerBound: UInt64 = try container.decode(UInt64.self, forKey: .inclusiveRangeFrom)
            let upperBound: UInt64 = try container.decode(UInt64.self, forKey: .inclusiveRangeTo)
            self = .inclusiveRange(lowerBound, upperBound)
        }
    }

    internal func includes(_ sequenceNumber: UInt64) -> Bool {
        switch self {
        case .single(let value):
            return sequenceNumber == value

        case let .inclusiveRange(lowerBound, upperBound):
            return lowerBound <= sequenceNumber && sequenceNumber <= upperBound
        }
    }

    internal func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .single(let value):
            try container.encode(DiscriminatorKeys.single, forKey: .discriminator)
            try container.encode(value, forKey: .singleValue)

        case let .inclusiveRange(lowerBound, upperBound):
            try container.encode(DiscriminatorKeys.inclusiveRange, forKey: .discriminator)
            try container.encode(lowerBound, forKey: .inclusiveRangeFrom)
            try container.encode(upperBound, forKey: .inclusiveRangeTo)
        }
    }

}
