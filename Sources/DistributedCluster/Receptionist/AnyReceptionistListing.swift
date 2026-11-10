import Distributed

internal protocol AnyReceptionistListing: Codable {
    // For comparing if two listings are equal
    var refsAsAnyHashable: AnyHashable { get }
}

extension AnyReceptionistListing {
    internal func unsafeUnwrapAs<T: AnyReceptionistListing>(_: T.Type) -> T {
        guard let unwrapped = self as? T else {
            fatalError("Type mismatch, expected: [\(T.self)] got [\(type(of: self as Any))]")
        }
        return unwrapped
    }
}
