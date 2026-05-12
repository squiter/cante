import Foundation

struct LyricsResult: Decodable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let syncedLyrics: String?
}

struct LyricLine {
    let startTime: TimeInterval
    let text: String
}

enum LyricsError: LocalizedError {
    case missingArgument(String)
    case invalidURL
    case requestFailed(Int)
    case noSyncedLyrics

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        case .invalidURL:
            return "Could not build LRCLIB URL."
        case .requestFailed(let statusCode):
            return "LRCLIB request failed with HTTP \(statusCode)."
        case .noSyncedLyrics:
            return "No synced lyrics found for this search."
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

            let result = try await fetchSyncedLyrics(track: track, artist: artist, album: album)
            let lines = parseLRC(result.syncedLyrics ?? "")

            guard !lines.isEmpty else {
                throw LyricsError.noSyncedLyrics
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

    private static func fetchSyncedLyrics(track: String, artist: String, album: String?) async throws -> LyricsResult {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist)
        ]

        if let album, !album.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "album_name", value: album))
        }

        guard let url = components?.url else {
            throw LyricsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Cante/0.1 (https://github.com/local/cante)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw LyricsError.requestFailed(httpResponse.statusCode)
        }

        let results = try JSONDecoder().decode([LyricsResult].self, from: data)

        guard let syncedResult = results.first(where: { result in
            guard let syncedLyrics = result.syncedLyrics else {
                return false
            }

            return !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw LyricsError.noSyncedLyrics
        }

        return syncedResult
    }

    private static func parseLRC(_ lyrics: String) -> [LyricLine] {
        lyrics
            .split(separator: "\n")
            .compactMap(parseLRCLine)
            .sorted { $0.startTime < $1.startTime }
    }

    private static func parseLRCLine(_ rawLine: Substring) -> LyricLine? {
        let line = String(rawLine)
        guard let closingBracket = line.firstIndex(of: "]") else {
            return nil
        }

        let timestampStart = line.index(after: line.startIndex)
        let timestamp = String(line[timestampStart..<closingBracket])
        let textStart = line.index(after: closingBracket)
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)

        guard !text.isEmpty, let startTime = parseTimestamp(timestamp) else {
            return nil
        }

        return LyricLine(startTime: startTime, text: text)
    }

    private static func parseTimestamp(_ timestamp: String) -> TimeInterval? {
        let parts = timestamp.split(separator: ":")

        guard parts.count == 2,
              let minutes = TimeInterval(parts[0]),
              let seconds = TimeInterval(parts[1]) else {
            return nil
        }

        return minutes * 60 + seconds
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
