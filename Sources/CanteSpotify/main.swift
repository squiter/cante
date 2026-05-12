import CanteCore
import AppKit
import Foundation

struct SpotifySnapshot: Equatable {
    let state: String
    let track: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval

    var trackKey: String {
        "\(artist)\u{1f}\(album)\u{1f}\(track)"
    }

    var isPlaying: Bool {
        state == "playing"
    }
}

enum SpotifyError: LocalizedError {
    case notRunning
    case scriptFailed(String)
    case invalidSnapshot(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Spotify is not running"
        case .scriptFailed(let message):
            return "Spotify script failed: \(message)"
        case .invalidSnapshot(let output):
            return "Could not parse Spotify output: \(output)"
        }
    }
}

@main
struct CanteSpotify {
    static func main() async {
        let pollInterval = argumentValue("poll-interval").flatMap(TimeInterval.init) ?? 0.5
        let printsDebug = CommandLine.arguments.contains("--debug")
        var currentTrackKey: String?
        var lines: [LyricLine] = []
        var lastStatusMessage: String?
        var lastPrintedLine: String?

        while true {
            do {
                let snapshot = try SpotifyReader.currentSnapshot()
                lastStatusMessage = nil

                if snapshot.trackKey != currentTrackKey {
                    currentTrackKey = snapshot.trackKey
                    lastPrintedLine = nil
                    lines = []

                    fputs("Spotify: \(snapshot.artist) - \(snapshot.track)\n", stderr)

                    do {
                        let result = try await LyricsClient.fetchSyncedLyrics(
                            track: snapshot.track,
                            artist: snapshot.artist,
                            album: snapshot.album,
                            duration: snapshot.duration
                        )
                        lines = LRCParser.parse(result.syncedLyrics ?? "")
                        fputs("Lyrics: \(lines.count) synced lines from LRCLIB\n", stderr)
                    } catch {
                        fputs("Lyrics: \(error.localizedDescription)\n", stderr)
                    }
                }

                if printsDebug {
                    fputs("Spotify: \(snapshot.state) @ \(String(format: "%.2f", snapshot.position))s\n", stderr)
                }

                if snapshot.isPlaying,
                   let currentLine = LyricTimeline.currentLine(in: lines, at: snapshot.position),
                   currentLine.text != lastPrintedLine {
                    print(currentLine.text, fflush: true)
                    lastPrintedLine = currentLine.text
                }
            } catch {
                let message = "cante-spotify: \(error.localizedDescription)"

                if message != lastStatusMessage {
                    fputs("\(message)\n", stderr)
                    lastStatusMessage = message
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private static func argumentValue(_ name: String) -> String? {
        var iterator = CommandLine.arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            guard argument == "--\(name)" else {
                continue
            }

            return iterator.next()
        }

        return nil
    }
}

enum SpotifyReader {
    private static let fieldSeparator = "\u{1f}"

    static func currentSnapshot() throws -> SpotifySnapshot {
        guard isSpotifyRunning else {
            throw SpotifyError.notRunning
        }

        let script = """
        tell application "Spotify"
          set trackName to name of current track
          set artistName to artist of current track
          set albumName to album of current track
          set durationSeconds to (duration of current track) / 1000
          set positionSeconds to player position
          set playbackState to player state as string
          return playbackState & ASCII character 31 & trackName & ASCII character 31 & artistName & ASCII character 31 & albumName & ASCII character 31 & durationSeconds & ASCII character 31 & positionSeconds
        end tell
        """

        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputText = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorText = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw SpotifyError.scriptFailed(errorText.isEmpty ? outputText : errorText)
        }

        let fields = outputText.components(separatedBy: fieldSeparator)

        guard fields.count == 6,
              let duration = parseAppleScriptNumber(fields[4]),
              let position = parseAppleScriptNumber(fields[5]) else {
            throw SpotifyError.invalidSnapshot(outputText)
        }

        return SpotifySnapshot(
            state: fields[0],
            track: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: duration,
            position: position
        )
    }

    private static func parseAppleScriptNumber(_ value: String) -> TimeInterval? {
        TimeInterval(value) ?? TimeInterval(value.replacingOccurrences(of: ",", with: "."))
    }

    private static var isSpotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == "com.spotify.client"
        }
    }
}

func print(_ value: String, fflush: Bool) {
    Swift.print(value)

    if fflush {
        Darwin.fflush(stdout)
    }
}
