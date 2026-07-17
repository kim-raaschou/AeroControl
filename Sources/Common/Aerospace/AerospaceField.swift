import Foundation

/// Single source of truth for the AeroSpace CLI's field names. Each case's name
/// matches the Swift property it decodes into; its raw value is the hyphenated
/// field key AeroSpace uses both in `%{...}` format tokens and in its JSON output.
///
/// Conforming to `CodingKey` lets the decoder structs use this enum directly as
/// their `CodingKeys`, so the tokens a command *requests* and the keys the parser
/// *reads* are literally the same enum — they cannot drift apart.
public enum AerospaceField: String, CaseIterable, CodingKey {
    case windowId = "window-id"
    case appName = "app-name"
    case appBundleId = "app-bundle-id"
    case workspace = "workspace"
    case parentLayout = "window-parent-container-layout"
    case monitorId = "monitor-id"

    /// The `%{field-key}` format token AeroSpace expects for this field.
    public var formatToken: String { "%{\(rawValue)}" }
}

extension Array where Element == AerospaceField {
    /// Joins these fields into the space-separated `--format` string AeroSpace's
    /// `--format` flag expects.
    public var formatString: String {
        map(\.formatToken).joined(separator: " ")
    }
}
