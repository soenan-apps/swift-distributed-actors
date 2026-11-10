import Logging

extension Children {
    /// Stops given child actor (if it exists) regardless of what type of messages it can handle.
    ///
    /// Returns: `true` if the child was stopped by this invocation, `false` otherwise
    internal func stop(named name: String) -> Bool {
        self.rwLock.withWriterLock {
            self.stopChild(named: name, includeAdapters: true)
        }
    }

    /// 指定に応じてadapterも含め、すべての子Actorへ停止を要求する。
    public func stopAll(includeAdapters: Bool = true) {
        self.rwLock.withWriterLockVoid {
            for name in self.container.keys {
                _ = self.stopChild(named: name, includeAdapters: includeAdapters)
            }
        }
    }

    // **CAUTION**: Only call this method when already holding `rwLock.writeLock`
    internal func stopChild(named name: String, includeAdapters: Bool) -> Bool {
        // implementation similar to find, however we do not care about the underlying type
        let childOpt: Child? = self.container[name]
        switch childOpt {
        case let .some(.cell(cell)) where self.markAsStoppingChildLocked(identifiedBy: cell.receivesSystemMessages.id):
            cell.receivesSystemMessages.sendSystemMessage(.stop, file: #filePath, line: #line)
            return true

        case let .some(.adapter(ref)) where includeAdapters:
            ref.stop()
            return self.container.removeValue(forKey: name) != nil

        default:
            return false
        }
    }
}
