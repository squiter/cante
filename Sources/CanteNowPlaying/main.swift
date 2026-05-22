import CanteCore
import AppKit
import Darwin
import Foundation

struct OverlayMessage: Encodable {
    let status: String?
    let current: String?
    let next: String?
    let track: String?
    let artist: String?
}

struct NowPlayingSnapshot: Equatable {
    let track: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let playbackRate: Double

    var trackKey: String {
        "\(artist)\u{1f}\(album)\u{1f}\(track)"
    }

    var isPlaying: Bool {
        playbackRate > 0
    }
}

enum NowPlayingError: LocalizedError {
    case frameworkUnavailable
    case noMedia
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            return "macOS MediaRemote framework is unavailable"
        case .noMedia:
            return "No macOS Now Playing media found"
        case .invalidSnapshot:
            return "Could not parse macOS Now Playing metadata"
        }
    }
}

@main
struct CanteNowPlaying {
    static func main() async {
        let pollInterval = argumentValue("poll-interval").flatMap(TimeInterval.init) ?? 0.5
        let printsDebug = CommandLine.arguments.contains("--debug")

        if CommandLine.arguments.contains("--dump") {
            await NowPlayingReader.dumpDebugInfo()
            return
        }

        if CommandLine.arguments.contains("--probe") {
            do {
                Foundation.exit(try await NowPlayingReader.currentSnapshot().isPlaying ? 0 : 1)
            } catch {
                Foundation.exit(1)
            }
        }

        var currentTrackKey: String?
        var lines: [LyricLine] = []
        var lastStatusMessage: String?
        var lastPrintedFrame: LyricFrame?
        var isShowingLoading = false
        var lyricsUnavailableTrackKey: String?

        while true {
            do {
                let snapshot = try await NowPlayingReader.currentSnapshot()
                lastStatusMessage = nil

                if snapshot.trackKey != currentTrackKey {
                    currentTrackKey = snapshot.trackKey
                    lastPrintedFrame = nil
                    lyricsUnavailableTrackKey = nil
                    lines = []
                    printLoadingMessage(track: snapshot.track, artist: snapshot.artist)
                    isShowingLoading = true

                    fputs("Now Playing: \(snapshot.artist) - \(snapshot.track)\n", stderr)

                    do {
                        let result = try await LyricsClient.fetchSyncedLyrics(
                            track: snapshot.track,
                            artist: snapshot.artist,
                            album: snapshot.album.isEmpty ? nil : snapshot.album,
                            duration: snapshot.duration
                        )
                        lines = LRCParser.parse(result.syncedLyrics ?? "")
                        fputs("Lyrics: \(lines.count) synced lines from LRCLIB\n", stderr)
                    } catch {
                        fputs("Lyrics: \(error.localizedDescription)\n", stderr)
                        lyricsUnavailableTrackKey = snapshot.trackKey
                        printNotFoundMessage(track: snapshot.track, artist: snapshot.artist)
                        isShowingLoading = false
                    }
                }

                if printsDebug {
                    fputs(
                        "Now Playing: \(snapshot.isPlaying ? "playing" : "paused") @ \(String(format: "%.2f", snapshot.position))s\n",
                        stderr
                    )
                }

                guard snapshot.isPlaying else {
                    if !isShowingLoading {
                        printLoadingMessage(track: snapshot.track, artist: snapshot.artist)
                        isShowingLoading = true
                    }

                    try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                    continue
                }

                guard lyricsUnavailableTrackKey != snapshot.trackKey else {
                    try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                    continue
                }

                if let currentFrame = LyricTimeline.currentFrame(in: lines, at: snapshot.position),
                   currentFrame != lastPrintedFrame {
                    printOverlayMessage(
                        current: currentFrame.current.text,
                        next: currentFrame.next?.text
                    )
                    lastPrintedFrame = currentFrame
                    isShowingLoading = false
                }
            } catch {
                let message = "cante-now-playing: \(error.localizedDescription)"

                if !isShowingLoading {
                    printLoadingMessage(track: nil, artist: nil)
                    isShowingLoading = true
                }

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

enum NowPlayingReader {
    private typealias GetNowPlayingInfo = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (NSDictionary?) -> Void
    ) -> Void
    private typealias RegisterForNotifications = @convention(c) (DispatchQueue) -> Void
    private typealias SetCanBeNowPlayingApplication = @convention(c) (Bool) -> Void

    private static let mediaRemotePath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private static let mediaRemoteBundlePath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
    private static var didPrepareAppKitHost = false

    static func currentSnapshot() async throws -> NowPlayingSnapshot {
        await prepareAppKitHost()
        try loadMediaRemote()
        registerForNotifications()
        setCanBeNowPlayingApplication(false)

        if let info = try await legacyNowPlayingInfo(), let snapshot = snapshot(from: info) {
            return snapshot
        }

        if let info = requestNowPlayingInfo(), let snapshot = snapshot(from: info) {
            return snapshot
        }

        if let info = scriptNowPlayingInfo(), let snapshot = snapshot(from: info) {
            return snapshot
        }

        if let info = await controllerNowPlayingInfo(), let snapshot = snapshot(from: info) {
            return snapshot
        }

        throw NowPlayingError.noMedia
    }

    static func dumpDebugInfo() async {
        await prepareAppKitHost()

        do {
            try loadMediaRemote()
            fputs("MediaRemote: loaded\n", stderr)
        } catch {
            fputs("MediaRemote: \(error.localizedDescription)\n", stderr)
            return
        }

        registerForNotifications()
        setCanBeNowPlayingApplication(false)

        let legacy = try? await legacyNowPlayingInfo()
        fputs("Legacy info keys: \(legacy?.count ?? 0)\n", stderr)
        if let legacy {
            dump(legacy)
        }

        let request = requestNowPlayingInfo()
        fputs("Request info keys: \(request?.count ?? 0)\n", stderr)
        if let request {
            dump(request)
        }

        let script = scriptNowPlayingInfo()
        fputs("Script info keys: \(script?.count ?? 0)\n", stderr)
        if let script {
            dump(script)
        }

        let controller = await controllerNowPlayingInfo()
        fputs("Controller info keys: \(controller?.count ?? 0)\n", stderr)
        if let controller {
            dump(controller)
        }

        if let snapshot = (
            legacy.flatMap(snapshot(from:))
            ?? request.flatMap(snapshot(from:))
            ?? script.flatMap(snapshot(from:))
            ?? controller.flatMap(snapshot(from:))
        ) {
            fputs("Snapshot: \(snapshot.artist) - \(snapshot.track) @ \(snapshot.position)s\n", stderr)
        } else {
            fputs("Snapshot: unavailable\n", stderr)
        }
    }

    @MainActor
    private static func prepareAppKitHost() {
        guard !didPrepareAppKitHost else {
            return
        }

        didPrepareAppKitHost = true
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    private static func loadMediaRemote() throws {
        guard dlopen(mediaRemotePath, RTLD_NOW | RTLD_GLOBAL) != nil,
              mediaRemoteBundle != nil else {
            throw NowPlayingError.frameworkUnavailable
        }
    }

    private static var mediaRemoteBundle: CFBundle? {
        let url = URL(fileURLWithPath: mediaRemoteBundlePath) as CFURL
        return CFBundleCreate(kCFAllocatorDefault, url)
    }

    private static func functionPointer(named name: String) -> UnsafeMutableRawPointer? {
        guard let bundle = mediaRemoteBundle else {
            return nil
        }

        return CFBundleGetFunctionPointerForName(bundle, name as CFString)
    }

    private static func dump(_ dictionary: NSDictionary) {
        for key in dictionary.allKeys.map({ "\($0)" }).sorted() {
            let value = dictionary[key] ?? ""
            let rendered: String
            if let data = value as? Data {
                rendered = "<\(data.count) bytes>"
            } else {
                rendered = "\(value)"
            }

            fputs("\(key): \(rendered)\n", stderr)
        }
    }

    private static func registerForNotifications() {
        guard let pointer = functionPointer(named: "MRMediaRemoteRegisterForNowPlayingNotifications") else {
            return
        }

        let register = unsafeBitCast(pointer, to: RegisterForNotifications.self)
        register(.main)
    }

    private static func setCanBeNowPlayingApplication(_ value: Bool) {
        guard let pointer = functionPointer(named: "MRMediaRemoteSetCanBeNowPlayingApplication") else {
            return
        }

        let setCanBe = unsafeBitCast(pointer, to: SetCanBeNowPlayingApplication.self)
        setCanBe(value)
    }

    private static func legacyNowPlayingInfo() async throws -> NSDictionary? {
        guard let pointer = functionPointer(named: "MRMediaRemoteGetNowPlayingInfo") else {
            return nil
        }

        let getInfo = unsafeBitCast(pointer, to: GetNowPlayingInfo.self)

        try? await Task.sleep(nanoseconds: 150_000_000)

        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false

            func resume(_ info: NSDictionary?) {
                lock.lock()
                defer { lock.unlock() }

                guard !didResume else {
                    return
                }

                didResume = true
                continuation.resume(returning: info)
            }

            getInfo(.main) { information in
                guard let information, information.count > 0 else {
                    resume(nil)
                    return
                }

                resume(information)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                resume(nil)
            }
        }
    }

    private static func requestNowPlayingInfo() -> NSDictionary? {
        guard let requestClass = NSClassFromString("MRNowPlayingRequest") as? NSObject.Type,
              let item = requestClass.perform(selector("localNowPlayingItem"))?.takeUnretainedValue() as? NSObject,
              let info = item.value(forKey: "nowPlayingInfo") as? NSDictionary,
              info.count > 0 else {
            return nil
        }

        return info
    }

    private static func scriptNowPlayingInfo() -> NSDictionary? {
        let script = """
        ObjC.import('Foundation');
        ObjC.import('AppKit');

        function plain(value) {
          if (value === undefined || value === null) {
            return null;
          }

          if (value.js !== undefined) {
            return value.js;
          }

          return String(value);
        }

        function run() {
          const mediaRemote = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
          mediaRemote.load;

          const request = $.NSClassFromString('MRNowPlayingRequest');
          if (!request) {
            return '{}';
          }

          const item = request.localNowPlayingItem;
          if (!item) {
            return '{}';
          }

          const info = item.nowPlayingInfo;
          if (!info) {
            return '{}';
          }

          const keys = [
            'kMRMediaRemoteNowPlayingInfoTitle',
            'kMRMediaRemoteNowPlayingInfoArtist',
            'kMRMediaRemoteNowPlayingInfoAlbum',
            'kMRMediaRemoteNowPlayingInfoDuration',
            'kMRMediaRemoteNowPlayingInfoElapsedTime',
            'kMRMediaRemoteNowPlayingInfoPlaybackRate',
            'kMRMediaRemoteNowPlayingInfoTimestamp'
          ];
          const result = {};

          for (const key of keys) {
            const value = plain(info.valueForKey(key));
            if (value !== null) {
              result[key] = value;
            }
          }

          return JSON.stringify(result);
        }
        """

        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !object.isEmpty else {
            return nil
        }

        return object as NSDictionary
    }

    private static func controllerNowPlayingInfo() async -> NSDictionary? {
        guard let destinationClass = NSClassFromString("MRDestination") as? NSObject.Type,
              let configurationClass = NSClassFromString("MRNowPlayingControllerConfiguration") as? NSObject.Type,
              let controllerClass = NSClassFromString("MRNowPlayingController") as? NSObject.Type,
              let destination = destinationClass.perform(selector("userSelectedDestination"))?.takeUnretainedValue()
        else {
            return nil
        }

        let configuration = configurationClass
            .perform(selector("alloc"))?
            .takeUnretainedValue() as? NSObject
        let initializedConfiguration = configuration?
            .perform(selector("initWithDestination:"), with: destination)?
            .takeUnretainedValue() as? NSObject
        initializedConfiguration?.setValue(false, forKey: "singleShot")
        initializedConfiguration?.setValue(true, forKey: "requestPlaybackState")
        initializedConfiguration?.setValue(true, forKey: "requestPlaybackQueue")

        guard let initializedConfiguration,
              let controllerAllocation = controllerClass
                .perform(selector("alloc"))?
                .takeUnretainedValue() as? NSObject,
              let controller = controllerAllocation
                .perform(selector("initWithConfiguration:"), with: initializedConfiguration)?
                .takeUnretainedValue() as? NSObject
        else {
            return nil
        }

        _ = controller.perform(selector("beginLoadingUpdates"))
        defer {
            _ = controller.perform(selector("endLoadingUpdates"))
        }

        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 100_000_000)

            guard let response = controller.value(forKey: "response") as? NSObject,
                  let info = infoDictionary(fromControllerResponse: response),
                  info.count > 0 else {
                continue
            }

            return info
        }

        return nil
    }

    private static func infoDictionary(fromControllerResponse response: NSObject) -> NSDictionary? {
        let info = NSMutableDictionary()

        if let playbackRate = numberValue(response.value(forKey: "playbackRate")) {
            info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = playbackRate
        } else if let playbackState = numberValue(response.value(forKey: "playbackState")) {
            info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = playbackState.intValue == 1 ? 1.0 : 0.0
        }

        guard let queue = response.value(forKey: "playbackQueue") as? NSObject,
              let items = queue.value(forKey: "contentItems") as? [NSObject],
              !items.isEmpty else {
            return info.count > 0 ? info : nil
        }

        let location = numberValue(queue.value(forKey: "location"))?.intValue ?? 0
        let safeLocation = max(0, min(Int(location), items.count - 1))

        guard let metadata = items[safeLocation].value(forKey: "metadata") as? NSObject else {
            return info.count > 0 ? info : nil
        }

        add(metadata.value(forKey: "title"), to: info, forKey: "kMRMediaRemoteNowPlayingInfoTitle")
        add(metadata.value(forKey: "trackArtistName"), to: info, forKey: "kMRMediaRemoteNowPlayingInfoArtist")
        add(metadata.value(forKey: "albumName"), to: info, forKey: "kMRMediaRemoteNowPlayingInfoAlbum")
        add(metadata.value(forKey: "duration"), to: info, forKey: "kMRMediaRemoteNowPlayingInfoDuration")
        add(metadata.value(forKey: "elapsedTime"), to: info, forKey: "kMRMediaRemoteNowPlayingInfoElapsedTime")

        if let extra = metadata.value(forKey: "nowPlayingInfo") as? NSDictionary {
            for key in extra.allKeys where info[key] == nil {
                info[key] = extra[key]
            }
        }

        return info.count > 0 ? info : nil
    }

    private static func snapshot(from info: NSDictionary) -> NowPlayingSnapshot? {
        guard let track = stringValue(info["kMRMediaRemoteNowPlayingInfoTitle"]),
              let artist = stringValue(info["kMRMediaRemoteNowPlayingInfoArtist"]),
              let duration = timeIntervalValue(info["kMRMediaRemoteNowPlayingInfoDuration"]) else {
            return nil
        }

        let album = stringValue(info["kMRMediaRemoteNowPlayingInfoAlbum"]) ?? ""
        let elapsedTime = timeIntervalValue(info["kMRMediaRemoteNowPlayingInfoElapsedTime"]) ?? 0
        let playbackRate = doubleValue(info["kMRMediaRemoteNowPlayingInfoPlaybackRate"]) ?? 0

        return NowPlayingSnapshot(
            track: track,
            artist: artist,
            album: album,
            duration: duration,
            position: calculatedPosition(
                elapsedTime: elapsedTime,
                playbackRate: playbackRate,
                timestamp: info["kMRMediaRemoteNowPlayingInfoTimestamp"]
            ),
            playbackRate: playbackRate
        )
    }

    private static func calculatedPosition(
        elapsedTime: TimeInterval,
        playbackRate: Double,
        timestamp: Any?
    ) -> TimeInterval {
        guard playbackRate > 0,
              let timestampDate = dateValue(timestamp) else {
            return elapsedTime
        }

        return elapsedTime + Date().timeIntervalSince(timestampDate) * playbackRate
    }

    private static func add(_ value: Any?, to dictionary: NSMutableDictionary, forKey key: String) {
        guard let value else {
            return
        }

        dictionary[key] = value
    }

    private static func selector(_ name: String) -> Selector {
        NSSelectorFromString(name)
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let value = value as? String {
            let trimmed = cleanString(value)
            return trimmed.isEmpty ? nil : trimmed
        }

        let string = cleanString("\(value)")
        return string.isEmpty ? nil : string
    }

    private static func cleanString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "(null)" ? "" : trimmed
    }

    private static func timeIntervalValue(_ value: Any?) -> TimeInterval? {
        doubleValue(value)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        numberValue(value)?.doubleValue
    }

    private static func numberValue(_ value: Any?) -> NSNumber? {
        if let value = value as? NSNumber {
            return value
        }

        if let value = value as? String, let number = Double(value) {
            return NSNumber(value: number)
        }

        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? Date {
            return value
        }

        guard let value = stringValue(value) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

func printOverlayMessage(current: String, next: String?) {
    let message = OverlayMessage(status: nil, current: current, next: next, track: nil, artist: nil)
    printMessage(message)
}

func printLoadingMessage(track: String?, artist: String?) {
    printMessage(OverlayMessage(status: "loading", current: nil, next: nil, track: track, artist: artist))
}

func printNotFoundMessage(track: String?, artist: String?) {
    printMessage(OverlayMessage(status: "not_found", current: nil, next: nil, track: track, artist: artist))
}

func printMessage(_ message: OverlayMessage) {
    if let data = try? JSONEncoder().encode(message),
       let encoded = String(data: data, encoding: .utf8) {
        Swift.print(encoded)
    } else {
        Swift.print("Cante")
    }

    Darwin.fflush(stdout)
}
