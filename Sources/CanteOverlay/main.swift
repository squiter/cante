import AppKit

final class LyricsView: NSVisualEffectView {
    private let textLabel = NSTextField(labelWithString: "Cante")
    private let subtitleLabel = NSTextField(labelWithString: "Waiting for lyrics on stdin...")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
        configureLabels()
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateText(_ text: String) {
        textLabel.stringValue = text.isEmpty ? " " : text
        subtitleLabel.stringValue = " "
    }

    private func configureView() {
        wantsLayer = true
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
    }

    private func configureLabels() {
        textLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        textLabel.textColor = .white
        textLabel.alignment = .center
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.maximumNumberOfLines = 2
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLayout() {
        addSubview(textLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 22),

            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            subtitleLabel.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
    }
}

final class OverlayController: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let lyricsView = LyricsView(frame: .zero)
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
        window.ignoresMouseEvents = true
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
                    self?.lyricsView.updateText(line)
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
