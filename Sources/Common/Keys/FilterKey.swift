import Foundation

public enum FilterKey: Equatable, Sendable {
    case character(Character)
    case backspace
    case enter
    case escape
    case move(StripMove)
}

public extension FilterKey {
    init?(keyCode: UInt16, characters: String?) {
        switch keyCode {
        case 53: self = .escape
        case 51: self = .backspace
        case 36, 76: self = .enter
        case 124: self = .move(.window(1))
        case 123: self = .move(.window(-1))
        case 126: self = .move(.row(-1))
        case 125: self = .move(.row(1))
        default:
            guard let key = characters?.first.flatMap(FilterKey.typed) else { return nil }
            self = key
        }
    }

    static func workspaceNamed(_ key: String) -> String? {
        guard key.count == 1, let c = key.first, typed(c) != nil else { return nil }
        return ["0": "10"][key] ?? key
    }

    static func typed(_ character: Character) -> FilterKey? {
        guard let scalar = character.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              scalar.value < 0xF700 else { return nil }
        return .character(character)
    }
}
