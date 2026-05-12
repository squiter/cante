import AppKit
import Foundation

struct OverlayMessage: Decodable {
    let status: String?
    let current: String?
    let next: String?
    let track: String?
    let artist: String?
}

final class LyricsView: NSVisualEffectView {
    private let textLabel = NSTextField(labelWithString: "Cante")
    private let subtitleLabel = NSTextField(labelWithString: "Loading your lyrics")
    private let closeButton = NSButton(title: "x", target: nil, action: nil)
    private let opaqueBackingView = NSView()
    private let config: OverlayConfig
    private var loadingTimer: Timer?
    private var dimTimer: Timer?
    private var loadingStep = 0

    init(frame frameRect: NSRect, config: OverlayConfig) {
        self.config = config
        super.init(frame: frameRect)
        configureView()
        configureOpaqueBackingView()
        configureLabels()
        configureCloseButton()
        configureLayout()
        startLoading()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateText(current: String, next: String?) {
        stopLoading()
        cancelDim()
        setTitle(current.isEmpty ? " " : current)
        setSubtitle(next?.isEmpty == false ? next ?? " " : " ")
    }

    func startLoading(title: String = "Cante") {
        cancelDim()
        setTitle(title.isEmpty ? "Cante" : title)
        updateLoadingText()

        guard loadingTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.advanceLoadingText()
        }

        RunLoop.main.add(timer, forMode: .common)
        loadingTimer = timer
    }

    func stopLoading() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        loadingStep = 0
    }

    func showNotFound(title: String) {
        stopLoading()
        cancelDim()
        setTitle(title.isEmpty ? "Cante" : title)
        setSubtitle("No synced lyrics found")

        let timer = Timer(timeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.dim()
        }

        RunLoop.main.add(timer, forMode: .common)
        dimTimer = timer
    }

    private func configureView() {
        wantsLayer = true
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
    }

    private func configureOpaqueBackingView() {
        opaqueBackingView.wantsLayer = true
        opaqueBackingView.layer?.backgroundColor = NSColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 0.92).cgColor
        opaqueBackingView.layer?.cornerRadius = 18
        opaqueBackingView.isHidden = !config.opaqueBackground
        opaqueBackingView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLabels() {
        textLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        textLabel.textColor = .white
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.maximumNumberOfLines = 2
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        applyShadowAttributes(to: textLabel, baseColor: .white)

        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        applyShadowAttributes(to: subtitleLabel, baseColor: NSColor.white.withAlphaComponent(0.68))
    }

    private func configureCloseButton() {
        closeButton.target = self
        closeButton.action = #selector(closeOverlay)
        closeButton.bezelStyle = .circular
        closeButton.font = .systemFont(ofSize: 12, weight: .bold)
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        closeButton.toolTip = "Close Cante"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLayout() {
        addSubview(opaqueBackingView)
        addSubview(textLabel)
        addSubview(subtitleLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            opaqueBackingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            opaqueBackingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            opaqueBackingView.topAnchor.constraint(equalTo: topAnchor),
            opaqueBackingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -58),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 22),

            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -58),
            subtitleLabel.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),

            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func setTitle(_ value: String) {
        if config.textShadow {
            textLabel.attributedStringValue = makeAttributedString(value, font: textLabel.font ?? .systemFont(ofSize: 34, weight: .semibold), color: .white)
        } else {
            textLabel.stringValue = value
        }
    }

    private func setSubtitle(_ value: String) {
        if config.textShadow {
            subtitleLabel.attributedStringValue = makeAttributedString(
                value,
                font: subtitleLabel.font ?? .systemFont(ofSize: 14, weight: .medium),
                color: NSColor.white.withAlphaComponent(0.68)
            )
        } else {
            subtitleLabel.stringValue = value
        }
    }

    private func makeAttributedString(_ value: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        return NSAttributedString(
            string: value,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .shadow: textShadow(),
                .paragraphStyle: paragraph
            ]
        )
    }

    private func textShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 4
        return shadow
    }

    private func applyShadowAttributes(to label: NSTextField, baseColor: NSColor) {
        guard config.textShadow else {
            return
        }

        label.attributedStringValue = makeAttributedString(
            label.stringValue,
            font: label.font ?? .systemFont(ofSize: 14),
            color: baseColor
        )
    }

    @objc private func closeOverlay() {
        NSApp.terminate(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    private func cancelDim() {
        dimTimer?.invalidate()
        dimTimer = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 1
        }
    }

    private func dim() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            animator().alphaValue = 0.18
        }
    }

    private func advanceLoadingText() {
        loadingStep = (loadingStep + 1) % 4
        updateLoadingText()
    }

    private func updateLoadingText() {
        setSubtitle("Loading your lyrics" + String(repeating: ".", count: loadingStep))
    }
}

final class OverlayController: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let lyricsView = LyricsView(
        frame: .zero,
        config: OverlayConfig.load(arguments: CommandLine.arguments)
    )
    private let inputReader = StandardInputReader(
        logsLines: CommandLine.arguments.contains("--debug-stdin")
    )
    private let signalController = SignalController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        signalController.start()
        createOverlayWindow()
        startReadingStandardInput()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lyricsView.stopLoading()
        inputReader.stop()
        OverlayRuntimeControl.removePID()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func createOverlayWindow() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(900, visibleFrame.width - 80), height: 132)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 88
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = lyricsView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = CommandLine.arguments.contains("--click-through")
        window.isMovableByWindowBackground = true
        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()

        self.window = window
    }

    private func startReadingStandardInput() {
        inputReader.start(
            onLine: { [weak self] line in
                DispatchQueue.main.async {
                    self?.updateOverlay(with: line)
                    self?.window?.orderFrontRegardless()
                }
            },
            onEnd: {
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        )
    }

    private func updateOverlay(with line: String) {
        guard let data = line.data(using: .utf8),
              let message = try? JSONDecoder().decode(OverlayMessage.self, from: data) else {
            lyricsView.updateText(current: line, next: nil)
            return
        }

        if message.status == "loading" {
            lyricsView.startLoading(title: loadingTitle(for: message))
            return
        }

        if message.status == "not_found" {
            lyricsView.showNotFound(title: loadingTitle(for: message))
            return
        }

        lyricsView.updateText(current: message.current ?? "", next: message.next)
    }

    private func loadingTitle(for message: OverlayMessage) -> String {
        guard let track = message.track, !track.isEmpty else {
            return "Cante"
        }

        guard let artist = message.artist, !artist.isEmpty else {
            return track
        }

        return "\(artist) - \(track)"
    }
}

final class StandardInputReader {
    private let input = FileHandle.standardInput
    private let logsLines: Bool
    private var buffer = Data()

    init(logsLines: Bool = false) {
        self.logsLines = logsLines
    }

    func start(onLine: @escaping (String) -> Void, onEnd: @escaping () -> Void) {
        input.readabilityHandler = { [weak self] handle in
            guard let self else {
                return
            }

            let data = handle.availableData

            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                self.emitRemainingBuffer(onLine: onLine)
                onEnd()
                return
            }

            self.buffer.append(data)
            self.emitCompleteLines(onLine: onLine)
        }
    }

    func stop() {
        input.readabilityHandler = nil
    }

    private func emitCompleteLines(onLine: (String) -> Void) {
        while let newline = buffer.firstIndex(of: 10) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            emit(lineData, onLine: onLine)
        }
    }

    private func emitRemainingBuffer(onLine: (String) -> Void) {
        guard !buffer.isEmpty else {
            return
        }

        emit(buffer, onLine: onLine)
        buffer.removeAll()
    }

    private func emit(_ data: Data, onLine: (String) -> Void) {
        let line = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .newlines)

        if logsLines {
            fputs("cante-overlay stdin: \(line)\n", stderr)
        }

        onLine(line)
    }
}

final class SignalController {
    private var sources: [DispatchSourceSignal] = []

    func start() {
        observe(SIGINT)
        observe(SIGTERM)
    }

    private func observe(_ signalNumber: Int32) {
        signal(signalNumber, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        sources.append(source)
    }
}

enum OverlayRuntimeControl {
    private static let pidFileURL = URL(fileURLWithPath: "/tmp/cante-overlay.pid")

    static func stopRunningOverlay() {
        guard let contents = try? String(contentsOf: pidFileURL, encoding: .utf8),
              let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            fputs("cante-overlay: no running overlay pid found\n", stderr)
            return
        }

        if kill(pid, SIGTERM) == 0 {
            removePID()
            fputs("cante-overlay: stopped overlay process \(pid)\n", stderr)
            return
        }

        if errno == ESRCH {
            removePID()
            fputs("cante-overlay: removed stale pid file for process \(pid)\n", stderr)
        } else {
            fputs("cante-overlay: failed to stop process \(pid): errno \(errno)\n", stderr)
        }
    }

    static func writePID() {
        let pid = ProcessInfo.processInfo.processIdentifier
        try? "\(pid)\n".write(to: pidFileURL, atomically: true, encoding: .utf8)
    }

    static func removePID() {
        try? FileManager.default.removeItem(at: pidFileURL)
    }
}

if CommandLine.arguments.contains("--stop") {
    OverlayRuntimeControl.stopRunningOverlay()
    exit(0)
}

let app = NSApplication.shared
let delegate = OverlayController()
app.delegate = delegate
OverlayRuntimeControl.writePID()
app.run()
