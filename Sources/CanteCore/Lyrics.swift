import Foundation

public struct LyricsResult: Decodable {
    public let trackName: String?
    public let artistName: String?
    public let albumName: String?
    public let duration: Double?
    public let syncedLyrics: String?
}

public struct LyricLine: Equatable {
    public let startTime: TimeInterval
    public let text: String

    public init(startTime: TimeInterval, text: String) {
        self.startTime = startTime
        self.text = text
    }
}

public struct LyricFrame: Equatable {
    public let current: LyricLine
    public let next: LyricLine?

    public init(current: LyricLine, next: LyricLine?) {
        self.current = current
        self.next = next
    }
}

public enum LyricsError: LocalizedError {
    case invalidURL
    case requestFailed(Int)
    case noSyncedLyrics

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build LRCLIB URL."
        case .requestFailed(let statusCode):
            return "LRCLIB request failed with HTTP \(statusCode)."
        case .noSyncedLyrics:
            return "No synced lyrics found for this search."
        }
    }
}

public enum LyricsClient {
    public static func fetchSyncedLyrics(
        track: String,
        artist: String,
        album: String?,
        duration: TimeInterval? = nil
    ) async throws -> LyricsResult {
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
        request.setValue("Cante/0.1 (https://github.com/squiter/cante)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw LyricsError.requestFailed(httpResponse.statusCode)
        }

        let results = try JSONDecoder().decode([LyricsResult].self, from: data)
        let syncedResults = results.filter { result in
            guard let syncedLyrics = result.syncedLyrics else {
                return false
            }

            return !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !syncedResults.isEmpty else {
            throw LyricsError.noSyncedLyrics
        }

        if let duration {
            return syncedResults.min { left, right in
                durationDistance(left.duration, duration) < durationDistance(right.duration, duration)
            } ?? syncedResults[0]
        }

        return syncedResults[0]
    }

    private static func durationDistance(_ candidate: Double?, _ target: TimeInterval) -> TimeInterval {
        guard let candidate else {
            return .greatestFiniteMagnitude
        }

        return abs(candidate - target)
    }
}

public enum LRCParser {
    public static func parse(_ lyrics: String) -> [LyricLine] {
        lyrics
            .split(separator: "\n")
            .compactMap(parseLine)
            .sorted { $0.startTime < $1.startTime }
    }

    private static func parseLine(_ rawLine: Substring) -> LyricLine? {
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
}

public enum LyricTimeline {
    public static func currentLine(in lines: [LyricLine], at playbackPosition: TimeInterval) -> LyricLine? {
        currentFrame(in: lines, at: playbackPosition)?.current
    }

    public static func currentFrame(in lines: [LyricLine], at playbackPosition: TimeInterval) -> LyricFrame? {
        var current: LyricLine?
        var next: LyricLine?

        for line in lines {
            guard line.startTime <= playbackPosition else {
                next = line
                break
            }

            current = line
        }

        guard let current else {
            return nil
        }

        return LyricFrame(current: current, next: next)
    }
}
