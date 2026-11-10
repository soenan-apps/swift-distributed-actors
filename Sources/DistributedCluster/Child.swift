import Logging

internal enum Child {
    case adapter(AbstractAdapter)
    case cell(AbstractShellProtocol)
}
