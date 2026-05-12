import CanteCore
import Foundation

enum LyricsError: LocalizedError {
    case missingArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        }
    }
}

@main
struct CanteLyrics {
    static func main() async {
        do {
            let arguments = parseArguments()
            let track = try requiredArgument("track", in: arguments)
            let artist = try requiredArgument("artist", in: arguments)
            let album = arguments["album"]
            let skipsIntro = arguments["skip-intro"] == "true"

            let result = try await LyricsClient.fetchSyncedLyrics(track: track, artist: artist, album: album)
            let lines = LRCParser.parse(result.syncedLyrics ?? "")

            guard !lines.isEmpty else {
                throw CanteCore.LyricsError.noSyncedLyrics
            }

            fputs("Streaming \(result.artistName ?? artist) - \(result.trackName ?? track)\n", stderr)
            stream(lines, skipsIntro: skipsIntro)
        } catch {
            fputs("cante-lyrics: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func parseArguments() -> [String: String] {
        var values: [String: String] = [:]
        var iterator = CommandLine.arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            guard argument.hasPrefix("--") else {
                continue
            }

            let key = String(argument.dropFirst(2))
            values[key] = iterator.next()
        }

        return values
    }

    private static func requiredArgument(_ name: String, in arguments: [String: String]) throws -> String {
        guard let value = arguments[name], !value.isEmpty else {
            throw LyricsError.missingArgument("--\(name)")
        }

        return value
    }

    private static func stream(_ lines: [LyricLine], skipsIntro: Bool) {
        let clockStart = Date()
        let lyricStart = skipsIntro ? lines[0].startTime : 0

        for line in lines {
            let targetDelay = line.startTime - lyricStart
            let elapsed = Date().timeIntervalSince(clockStart)
            let remaining = targetDelay - elapsed

            if remaining > 0 {
                Thread.sleep(forTimeInterval: remaining)
            }

            print(line.text, fflush: true)
        }
    }
}

func print(_ value: String, fflush: Bool) {
    Swift.print(value)

    if fflush {
        Darwin.fflush(stdout)
    }
}
