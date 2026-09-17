import Foundation

/// AeroSpace events carry no data. Every field the overview shows — focus included — is
/// read with a command, so an event only ever means "read again". That keeps a dropped or
/// out-of-order event costly in latency but never in correctness: a reload is idempotent
/// and re-derives the truth, where a payload-carrying event would leave a drift that
/// nothing heals.
public enum AerospaceEvent: Equatable, Sendable {
    /// Something changed in AeroSpace.
    case changed
    /// A name we do not act on.
    case other
}
