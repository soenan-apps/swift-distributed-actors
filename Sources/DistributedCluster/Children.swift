import Dispatch
import Logging
import NIO

/// 子Actorを名前で管理する。繰り返し参照する場合はActorRefを保持する。
public class Children {
    // Implementation note: access is optimized for fetching by name, as that's what we do during child lookup
    // as well as actor tree traversal.
    internal var container: [String: Child]
    internal var stopping: [ActorID: AbstractShellProtocol]
    // **CAUTION**: All access to `container` or `stopping` must be protected by `rwLock`
    internal let rwLock: ReadWriteLock

    @usableFromInline internal var isEmpty: Bool {
        self.rwLock.withReaderLock {
            self.container.isEmpty && self.stopping.isEmpty
        }
    }

    @inlinable internal var nonEmpty: Bool {
        !self.isEmpty
    }

    /// 空の子Actorコレクションを作る。
    public init() {
        self.container = [:]
        self.stopping = [:]
        self.rwLock = ReadWriteLock()
    }

    /// 指定したパスに対応する子Actorが存在するかを調べる。
    public func hasChild(identifiedBy path: ActorPath) -> Bool {
        self.rwLock.withReaderLock {
            switch self.container[path.name] {
            case let .some(.cell(child)):
                return child.receivesSystemMessages.id.path == path

            case let .some(.adapter(child)):
                return child.id.path == path

            case .none:
                return false
            }
        }
    }

    /// 指定したIDのパスに対応する子Actorが存在するかを調べる。
    public func hasChild(identifiedBy id: ActorID) -> Bool {
        self.hasChild(identifiedBy: id.path)
    }

    /// 名前とメッセージ型に対応する子Actorを返す。
    public func find<T>(named name: String, withType _: T.Type) -> ActorRef<T>? {
        self.rwLock.withReaderLock {
            switch self.container[name] {
            case let .some(.cell(child)):
                return child.receivesSystemMessages as? ActorRef<T>

            case let .some(.adapter(adapter)):
                return ActorRef<T>(.adapter(adapter))

            case .none:
                return nil
            }
        }
    }

    /// 名前に対応する子ActorのIDを返す。
    public func findID(named name: String) -> ActorID? {
        self.rwLock.withReaderLock {
            switch self.container[name] {
            case let .some(.cell(child)):
                return child.asAddressable.id

            case let .some(.adapter(adapter)):
                return adapter.id

            case .none:
                return nil
            }
        }
    }

    internal func insert<T, R: ActorShell<T>>(_ childCell: R) {
        self.rwLock.withWriterLockVoid {
            self.container[childCell.id.name] = .cell(childCell)
        }
    }

    internal func insert<R: AbstractAdapter>(_ adapterRef: R) {
        self.rwLock.withWriterLockVoid {
            self.container[adapterRef.id.name] = .adapter(adapterRef)
        }
    }

    /// Imprecise contains function, which only checks for the existence of a child actor by its name,
    /// without taking into account its incarnation number.
    ///
    /// - SeeAlso: `contains(identifiedBy:)`
    internal func contains(name: String) -> Bool {
        self.rwLock.withReaderLock {
            self.container.keys.contains(name)
        }
    }

    /// Precise contains function, which checks if this children container contains the specific actor
    /// identified by the passed in path.
    ///
    /// - SeeAlso: `contains(name:)`
    internal func contains(identifiedBy id: ActorID) -> Bool {
        self.rwLock.withReaderLock {
            switch self.container[id.name] {
            case let .some(.cell(child)):
                return child.receivesSystemMessages.id == id

            case let .some(.adapter(child)):
                return child.id == id

            case .none:
                return false
            }
        }
    }

    /// INTERNAL API: Only the ActorCell may mutate its children collection (as a result of spawning or stopping them).
    /// Returns: `true` upon successful removal of the ref identified by passed in path, `false` otherwise
    @usableFromInline
    @discardableResult
    internal func removeChild(identifiedBy id: ActorID) -> Bool {
        self.rwLock.withWriterLock {
            switch self.container[id.name] {
            case let .some(.cell(child)) where child.receivesSystemMessages.id.incarnation == id.incarnation:
                return self.container.removeValue(forKey: id.name) != nil

            case let .some(.adapter(child)) where child.id.incarnation == id.incarnation:
                return self.container.removeValue(forKey: id.name) != nil

            default:
                return self.stopping.removeValue(forKey: id) != nil
            }
        }
    }

    /// INTERNAL API: Only the ActorCell may mutate its children collection (as a result of spawning or stopping them).
    ///
    /// Once marked as stopping the actor MUST be sent a `.stop` system message.
    ///
    /// Returns: `true` upon successfully marking the ref identified by passed in path as stopping
    @usableFromInline
    @discardableResult
    internal func markAsStoppingChild(identifiedBy id: ActorID) -> Bool {
        self.rwLock.withWriterLock {
            self.markAsStoppingChildLocked(identifiedBy: id)
        }
    }

    // **CAUTION**: Only call this method when already holding `rwLock.writeLock`
    @usableFromInline
    @discardableResult
    internal func markAsStoppingChildLocked(identifiedBy id: ActorID) -> Bool {
        switch self.container.removeValue(forKey: id.name) {
        case let .some(.cell(child)) where child.asAddressable.id.incarnation == id.incarnation:
            self.stopping[id] = child
            return true

        case let .some(.adapter(child)) where child.id.incarnation == id.incarnation:
            // adapters don't have to be stopped as they are not real actors, so removing is sufficient
            self.container.removeValue(forKey: id.name)
            return true

        default:
            return false
        }
    }

    @usableFromInline
    internal func forEach(_ body: (AddressableActorRef) throws -> Void) rethrows {
        try self.rwLock.withReaderLock {
            for value in self.container.values {
                switch value {
                case let .cell(child):
                    try body(child.asAddressable)

                case .adapter:
                    ()  // do not apply onto adapters, only real actors
                }
            }
        }
    }
}
