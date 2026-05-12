import Foundation

enum OverlaySize: String {
    case small
    case medium
    case large

    var scale: CGFloat {
        switch self {
        case .small: return 0.7
        case .medium: return 1.0
        case .large: return 1.3
        }
    }
}

struct OverlayConfig {
    var textShadow: Bool
    var opaqueBackground: Bool
    var size: OverlaySize
    var singleLine: Bool

    static let defaults = OverlayConfig(
        textShadow: false,
        opaqueBackground: false,
        size: .medium,
        singleLine: false
    )

    static func load(arguments: [String]) -> OverlayConfig {
        var config = loadFromFile() ?? .defaults
        config.apply(arguments: arguments)
        return config
    }

    private static func loadFromFile() -> OverlayConfig? {
        let url = configFileURL()

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let overlay = json["overlay"] as? [String: Any] ?? [:]
        return OverlayConfig(
            textShadow: overlay["textShadow"] as? Bool ?? defaults.textShadow,
            opaqueBackground: overlay["opaqueBackground"] as? Bool ?? defaults.opaqueBackground,
            size: (overlay["size"] as? String).flatMap(OverlaySize.init(rawValue:)) ?? defaults.size,
            singleLine: overlay["singleLine"] as? Bool ?? defaults.singleLine
        )
    }

    private static func configFileURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("cante", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private mutating func apply(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--text-shadow":
                textShadow = true
            case "--no-text-shadow":
                textShadow = false
            case "--opaque":
                opaqueBackground = true
            case "--no-opaque":
                opaqueBackground = false
            case "--single-line":
                singleLine = true
            case "--no-single-line":
                singleLine = false
            case "--size":
                if let value = arguments[safe: index + 1],
                   let parsed = OverlaySize(rawValue: value) {
                    size = parsed
                    index += 1
                }
            default:
                if let value = parseInlineSize(argument) {
                    size = value
                }
            }

            index += 1
        }
    }

    private func parseInlineSize(_ argument: String) -> OverlaySize? {
        let prefix = "--size="
        guard argument.hasPrefix(prefix) else {
            return nil
        }

        let value = String(argument.dropFirst(prefix.count))
        return OverlaySize(rawValue: value)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
