import Distributed
import Logging

/// 配送できなかったメッセージを扱う参照。実際のActorとしては実行されない。
/// watchには即座にexistenceConfirmed:falseの終了通知を返す。
/// 終了済み参照と、最初から解決できなかったdead referenceの両方を扱う。
public final class DeadLetterOffice {
    internal let actorID: ActorID
    internal let log: Logger
    internal weak var system: ClusterSystem?
    internal let isShuttingDown: () -> Bool

    @usableFromInline internal var id: ActorID {
        self.actorID
    }

    @usableFromInline internal var path: ActorPath {
        self.actorID.path
    }

    @usableFromInline internal var ref: ActorRef<DeadLetter> {
        .init(.deadLetters(self))
    }

    internal init(_ log: Logger, id: ActorID, system: ClusterSystem?) {
        self.log = log
        self.actorID = id
        self.system = system
        self.isShuttingDown = { [weak system] in
            system?.isShuttingDown ?? false
        }
    }

    internal func deliver(_ message: Any, file: String = #filePath, line: UInt = #line) {
        if let alreadyDeadLetter = message as? DeadLetter {
            self.onDeadLetter(
                alreadyDeadLetter,
                file: alreadyDeadLetter.sentAtFile ?? file,
                line: alreadyDeadLetter.sentAtLine ?? line
            )
        } else {
            self.onDeadLetter(
                DeadLetter(message, recipient: self.id, sentAtFile: file, sentAtLine: line),
                file: file,
                line: line
            )
        }
    }

    private func onDeadLetter(_ deadLetter: DeadLetter, file: String, line: UInt) {
        // Implementation notes:
        // We do want to change information in the logger; but we do NOT want to create a new logger
        // as that may then change ordering; if multiple onDeadLetter executions are ongoing, we want
        // all of them to be piped to the exact same logging handler, do not create a new Logging.Logger() here (!)

        var metadata: Logger.Metadata = [:]

        let recipientString: String
        if let recipient = deadLetter.recipient {
            let deadID: ActorID = .init(
                remote: recipient.node,
                path: recipient.path,
                incarnation: recipient.incarnation
            )

            // should not really happen, as the only way to get a remote ref is to resolve it, and a remote resolve
            // always yields a remote ref
            // thus, it is impossible to resolve a remote address into a dead ref; however keeping this path in case we
            // manually make such mistake
            // somewhere in internals, and can spot it then easily
            if recipient.path.starts(with: .systemRoot), self.isShuttingDown() {
                return  // do not log dead letters to /system actors while shutting down
            }

            metadata["actor/path"] = Logger.MetadataValue.stringConvertible(deadID.path)
            recipientString = "to [\(recipient.detailedDescription)]"
        } else {
            recipientString = ""
        }

        if let systemMessage = deadLetter.message as? SystemMessages,
            self.specialHandled(systemMessage, recipient: deadLetter.recipient) {
            return  // system message was special handled; no need to log it anymore
        }

        // in all other cases, we want to log the dead letter:
        self.log.notice(
            "Dead letter was not delivered \(recipientString)",
            metadata: { () -> Logger.Metadata in
                // more metadata (from Envelope) (e.g. sender)
                if let recipient = deadLetter.recipient?.detailedDescription {
                    metadata["deadLetter/recipient"] = "\(recipient)"
                }
                if let invocation = deadLetter.message as? InvocationMessage {
                    metadata["deadLetter/invocation/target"] = "\(invocation.target.description)"
                }
                metadata["deadLetter/location"] = "\(file):\(line)"
                metadata["deadLetter/message"] = "\(deadLetter.message)"
                metadata["deadLetter/message/type"] = "\(String(reflecting: type(of: deadLetter.message)))"
                return metadata
            }()
        )
    }

    private func specialHandled(_ message: SystemMessages, recipient: ActorID?) -> Bool {
        // special handle $ask- replies; those mean we got a reply to an ask which timed out already

        switch message {
        case .tombstone:
            // this should never happen; tombstone must always be taken in by the actor as last message
            traceLog_Mailbox(
                self.id.path,
                "Tombstone arrived in dead letters. TODO: make sure these dont happen",
                file: #fileID,
                line: #line
            )
            return true

        case let .watch(watchee, watcher):
            // if a watch message arrived here it either:
            // A posthumous watch can arrive after the tombstone was drained.
            // Watching dead letters directly also immediately notifies the watcher.
            watcher.sendSystemMessage(
                .terminated(ref: watchee, existenceConfirmed: false),
                file: #filePath,
                line: #line
            )
            return true

        case .stop:
            // we special handle some not delivered stop messages, based on the fact that those
            // are inherently racy in the during actor system shutdown:
            return recipient?.path == .clusterShellPath

        default:
            return self.isShuttingDown()
        }
    }
}
