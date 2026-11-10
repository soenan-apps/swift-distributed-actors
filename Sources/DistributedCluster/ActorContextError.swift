import Foundation

/// Errors which can occur while executing actions on the [ActorContext].
public struct ActorContextError: Error, CustomStringConvertible {
    internal enum ActorContextErrorKind {
        /// システムの停止中に新しいActorを作成しようとした。
        case alreadyStopping(String)
        /// 自分自身の停止にはcontext.stopではなくBehavior.stopを使用する。
        case attemptedStoppingMyselfUsingContext(ref: AddressableActorRef)
        /// 子Actorではない参照を停止しようとした。
        case attemptedStoppingNonChildActor(ref: AddressableActorRef)
        /// 同じパスに存在するActorと名前が重複した。
        case duplicateActorPath(path: ActorPath, existing: ActorID)
    }

    internal class Storage {
        internal let error: ActorContextErrorKind
        internal let file: String
        internal let line: UInt

        internal init(error: ActorContextErrorKind, file: String, line: UInt) {
            self.error = error
            self.file = file
            self.line = line
        }
    }

    internal let underlying: Storage

    public var description: String {
        "\(Self.self)(\(self.underlying.error), at: \(self.underlying.file):\(self.underlying.line))"
    }

    internal init(_ error: ActorContextErrorKind, file: String = #fileID, line: UInt = #line) {
        self.underlying = Storage(error: error, file: file, line: line)
    }
}
