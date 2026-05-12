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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createOverlayWindow()
        startReadingStandardInput()
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let line = readLine() {
                DispatchQueue.main.async {
                    self?.lyricsView.updateText(line)
                }
            }

            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = OverlayController()
app.delegate = delegate
app.run()
