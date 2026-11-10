import Foundation

internal struct GossiperTestPayload: Codable {
    internal let metadata: String
    internal let payload: String

    internal init(_ info: String) {
        self.metadata = info
        self.payload = info
    }
}
