import Foundation

struct OverlayConfig {
    var textShadow: Bool
    var opaqueBackground: Bool

    static let defaults = OverlayConfig(textShadow: false, opaqueBackground: false)

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
            opaqueBackground: overlay["opaqueBackground"] as? Bool ?? defaults.opaqueBackground
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
        for argument in arguments {
            switch argument {
            case "--text-shadow":
                textShadow = true
            case "--no-text-shadow":
                textShadow = false
            case "--opaque":
                opaqueBackground = true
            case "--no-opaque":
                opaqueBackground = false
            default:
                continue
            }
        }
    }
}
