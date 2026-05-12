import CanteCore
import Darwin
import Foundation

@main
struct CanteCLI {
    private static var childProcesses: [Process] = []
    private static var signalSources: [DispatchSourceSignal] = []
    private static let supervisorPidPath = "/tmp/cante.pid"

    static func main() {
        do {
            let firstArgument = CommandLine.arguments.dropFirst().first
            let helpFlags: Set<String> = ["help", "--help", "-h"]
            let isHelp = firstArgument.map(helpFlags.contains) ?? false
            let looksLikeFlag = !isHelp && (firstArgument?.hasPrefix("-") == true)
            let command = isHelp ? "help" : (looksLikeFlag ? "run" : (firstArgument ?? "run"))
            let runArguments = looksLikeFlag
                ? Array(CommandLine.arguments.dropFirst())
                : Array(CommandLine.arguments.dropFirst(2))

            switch command {
            case "run":
                let foregroundFlags: Set<String> = ["--foreground", "-f"]
                let foreground = runArguments.contains(where: foregroundFlags.contains)
                let cleanedArguments = runArguments.filter { !foregroundFlags.contains($0) }
                if foreground {
                    try runSpotifyOverlay(arguments: cleanedArguments)
                } else {
                    try daemonize(arguments: cleanedArguments)
                }
            case "stop":
                try stopRunning()
            case "clear-cache":
                try LyricsClient.clearCache()
                fputs("cante: cleared lyrics cache\n", stderr)
            case "help":
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

    private static func daemonize(arguments: [String]) throws {
        let logURL = logFileURL()
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        logHandle.seekToEndOfFile()

        let child = Process()
        child.executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["run", "--foreground"] + arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = logHandle
        child.standardError = logHandle
        try child.run()

        let pid = child.processIdentifier
        try "\(pid)\n".write(toFile: supervisorPidPath, atomically: true, encoding: .utf8)

        print("cante: started in background (pid \(pid))")
        print("Logs:  \(logURL.path)")
        print("Stop:  cante stop")
    }

    private static func runSpotifyOverlay(arguments: [String]) throws {
        if isatty(STDIN_FILENO) == 0 {
            _ = Darwin.setsid()
        }

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
        clearSupervisorPidFileIfOwned()
    }

    private static func stopRunning() throws {
        var supervisorSignalled = false
        if let pidString = try? String(contentsOfFile: supervisorPidPath, encoding: .utf8),
           let pid = pid_t(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            if kill(pid, SIGTERM) == 0 {
                supervisorSignalled = true
                fputs("cante: stopped (pid \(pid))\n", stderr)
            } else if errno != ESRCH {
                fputs("cante: failed to stop pid \(pid): errno \(errno)\n", stderr)
            }
            try? FileManager.default.removeItem(atPath: supervisorPidPath)
        }

        if !supervisorSignalled {
            try runSiblingExecutable("cante-overlay", arguments: ["--stop"])
        }
    }

    private static func clearSupervisorPidFileIfOwned() {
        guard let pidString = try? String(contentsOfFile: supervisorPidPath, encoding: .utf8),
              let pid = pid_t(pidString.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid == getpid()
        else {
            return
        }
        try? FileManager.default.removeItem(atPath: supervisorPidPath)
    }

    private static func logFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/cante.log")
    }

    private static func overlayArguments(from arguments: [String], debug: Bool) -> [String] {
        let passthroughFlags: Set<String> = [
            "--click-through",
            "--text-shadow",
            "--no-text-shadow",
            "--opaque",
            "--no-opaque",
            "--single-line",
            "--no-single-line"
        ]

        var result = debug ? ["--debug-stdin"] : []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            if passthroughFlags.contains(argument) {
                result.append(argument)
            } else if argument == "--size", let value = arguments[safe: index + 1] {
                result.append(argument)
                result.append(value)
                index += 1
            } else if argument.hasPrefix("--size=") {
                result.append(argument)
            }

            index += 1
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
        let directory = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        return directory.appendingPathComponent(name)
    }

    private static func installSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                terminateChildren()
                clearSupervisorPidFileIfOwned()
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
              cante run [--foreground|-f] [--debug] [--click-through]
                        [--text-shadow|--no-text-shadow]
                        [--opaque|--no-opaque]
                        [--size small|medium|large]
                        [--single-line|--no-single-line]
              cante stop
              cante clear-cache

            Commands:
              run          Start Spotify-synced lyrics in the overlay.
                           Detaches by default; output goes to
                           ~/Library/Logs/cante.log. Pass --foreground / -f to
                           keep cante in the current terminal (Ctrl-C stops it).
              stop         Stop the running overlay (and the background
                           supervisor, if there is one).
              clear-cache  Remove cached LRCLIB lyrics.

            Overlay options:
              --text-shadow / --no-text-shadow   Toggle the dark halo around lyric text.
              --opaque      / --no-opaque        Toggle the opaque dark backdrop.
              --size <preset>                    Scale the overlay (small, medium, large).
              --single-line / --no-single-line   Show only the current lyric line.

            Persistent defaults can be set in ~/.config/cante/config.json:
              {
                "overlay": {
                  "textShadow": true,
                  "opaqueBackground": false,
                  "size": "medium",
                  "singleLine": false
                }
              }
            """
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
