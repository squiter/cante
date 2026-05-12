import CanteCore
import Foundation

@main
struct CanteCLI {
    private static var childProcesses: [Process] = []
    private static var signalSources: [DispatchSourceSignal] = []

    static func main() {
        do {
            let command = CommandLine.arguments.dropFirst().first ?? "run"

            switch command {
            case "run":
                try runSpotifyOverlay(arguments: Array(CommandLine.arguments.dropFirst(2)))
            case "stop":
                try runSiblingExecutable("cante-overlay", arguments: ["--stop"])
            case "clear-cache":
                try LyricsClient.clearCache()
                fputs("cante: cleared lyrics cache\n", stderr)
            case "help", "--help", "-h":
                printHelp()
            default:
                fputs("cante: unknown command '\(command)'\n\n", stderr)
                printHelp()
                Foundation.exit(64)
            }
        } catch {
            fputs("cante: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func runSpotifyOverlay(arguments: [String]) throws {
        let spotify = Process()
        let overlay = Process()
        let pipe = Pipe()
        let debug = arguments.contains("--debug")

        spotify.executableURL = executableURL(named: "cante-spotify")
        spotify.arguments = debug ? ["--debug"] : []
        spotify.standardOutput = pipe
        spotify.standardError = FileHandle.standardError

        overlay.executableURL = executableURL(named: "cante-overlay")
        overlay.arguments = overlayArguments(from: arguments, debug: debug)
        overlay.standardInput = pipe
        overlay.standardError = FileHandle.standardError

        installSignalHandlers()

        childProcesses = [spotify, overlay]
        try overlay.run()
        try spotify.run()

        overlay.waitUntilExit()
        terminateChildren()
    }

    private static func overlayArguments(from arguments: [String], debug: Bool) -> [String] {
        let passthroughFlags: Set<String> = [
            "--click-through",
            "--text-shadow",
            "--no-text-shadow",
            "--opaque",
            "--no-opaque"
        ]

        var result = debug ? ["--debug-stdin"] : []
        for argument in arguments where passthroughFlags.contains(argument) {
            result.append(argument)
        }
        return result
    }

    private static func runSiblingExecutable(_ name: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL(named: name)
        process.arguments = arguments
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
    }

    private static func executableURL(named name: String) -> URL {
        let currentExecutable = URL(fileURLWithPath: CommandLine.arguments[0])
        let directory = currentExecutable.deletingLastPathComponent()
        return directory.appendingPathComponent(name)
    }

    private static func installSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                terminateChildren()
                Foundation.exit(signalNumber == SIGINT ? 130 : 143)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private static func terminateChildren() {
        for process in childProcesses where process.isRunning {
            process.terminate()
        }
    }

    private static func printHelp() {
        print(
            """
            Usage:
              cante run [--debug] [--click-through] [--text-shadow|--no-text-shadow] [--opaque|--no-opaque]
              cante stop
              cante clear-cache

            Commands:
              run          Start Spotify-synced lyrics in the overlay.
              stop         Close the running overlay.
              clear-cache  Remove cached LRCLIB lyrics.

            Overlay options:
              --text-shadow / --no-text-shadow   Toggle the dark halo around lyric text.
              --opaque      / --no-opaque        Toggle the opaque dark backdrop.

            Persistent defaults can be set in ~/.config/cante/config.json:
              { "overlay": { "textShadow": true, "opaqueBackground": false } }
            """
        )
    }
}
