import DistributedActorsConcurrencyHelpers

/// メタデータとともにメールボックスへ格納するメッセージ。
internal struct Payload {
    internal let payload: WrappedMessage

    #if SACT_DEBUG
    internal let senderAddress: ActorID
    #endif
}

/// Actorのコンテキストで後から実行するクロージャ。
@usableFromInline
internal struct ActorClosureCarry: CustomStringConvertible {
    @usableFromInline
    internal class Storage {
        @usableFromInline internal let function: () throws -> Void
        @usableFromInline internal let file: String
        @usableFromInline internal let line: UInt

        @usableFromInline
        internal init(function: @escaping () throws -> Void, file: String, line: UInt) {
            self.function = function
            self.file = file
            self.line = line
        }
    }

    internal let storage: Storage

    @usableFromInline internal var function: () throws -> Void {
        self.storage.function
    }

    @usableFromInline internal var file: String {
        self.storage.file
    }

    @usableFromInline internal var line: UInt {
        self.storage.line
    }

    @usableFromInline internal var description: String {
        "ActorClosureCarry(<closure> defined at \(self.storage.file):\(self.storage.line))"
    }

    @usableFromInline
    internal init(function: @escaping () throws -> Void, file: String, line: UInt) {
        self.storage = .init(function: function, file: file, line: line)
    }
}

@usableFromInline
internal struct SubMessageCarry: CustomStringConvertible {
    @usableFromInline
    internal class Storage {
        @usableFromInline internal let identifier: AnySubReceiveId
        @usableFromInline internal let message: Any
        @usableFromInline internal let subReceiveAddress: ActorID

        @usableFromInline
        internal init(identifier: AnySubReceiveId, message: Any, subReceiveAddress: ActorID) {
            self.identifier = identifier
            self.message = message
            self.subReceiveAddress = subReceiveAddress
        }
    }

    internal let storage: Storage

    @usableFromInline internal var identifier: AnySubReceiveId {
        self.storage.identifier
    }

    @usableFromInline internal var message: Any {
        self.storage.message
    }

    @usableFromInline internal var subReceiveAddress: ActorID {
        self.storage.subReceiveAddress
    }

    @usableFromInline internal var description: String {
        "SubMessageCarry(\(self.message), subReceive identifier: \(self.identifier.underlying), "
            + "id: \(self.subReceiveAddress))"
    }

    @usableFromInline
    internal init(identifier: AnySubReceiveId, message: Any, subReceiveAddress: ActorID) {
        self.storage = .init(identifier: identifier, message: message, subReceiveAddress: subReceiveAddress)
    }
}

@usableFromInline
internal struct AdaptedMessageCarry {
    @usableFromInline internal let message: Any
}

@usableFromInline
internal enum ActorRunResult {
    case closed
    case continueRunning
    case shouldStop
    case shouldSuspend
}

/// メッセージ処理に失敗したActorとバックトレースを説明する内部API。
public struct MessageProcessingFailure: Error, CustomStringConvertible, CustomDebugStringConvertible {
    internal let messageDescription: String
    internal let backtrace: [String]

    public var description: String {
        "Actor faulted while processing message '\(self.messageDescription)', with backtrace"
    }

    public var debugDescription: String {
        let backtraceStr: String = self.backtrace.joined(separator: "\n")
        return "Actor faulted while processing message '\(self.messageDescription)':\n\(backtraceStr)"
    }
}

// Type erasure avoids per-message metatype overhead when dequeuing messages.
internal enum WrappedMessage: NotActuallyCodableMessage {
    case adaptedMessage(AdaptedMessageCarry)
    case closure(ActorClosureCarry)
    case message(Any)
    case subMessage(SubMessageCarry)
}
