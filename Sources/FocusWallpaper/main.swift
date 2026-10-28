import AppKit
import UniformTypeIdentifiers
import FocusWallpaperCore

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let desktop = DesktopPresentation()
    private lazy var presentation = FocusPresentation(
        show: { [unowned self] in try desktop.show($0) },
        hide: { [unowned self] in desktop.hide() })
    private let defaults = UserDefaults.standard
    private let focusReader = LocalFocusReader()
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var monitoring = false
    private var ready = false
    private var lastPreviewURL: URL?
    private var errorMessage: String?
    private let preview = WallpaperPreview()
    private let emptyPreview = NSTextField(labelWithString: "Choose a Focus wallpaper")
    private let status = NSTextField(labelWithString: "Preparing…")
    private let dot = NSImageView()
    private let toggle = NSButton(title: "Start", target: nil, action: nil)
    private let choose = NSButton(title: "Choose…", target: nil, action: nil)
    private let detail = NSButton(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Status details")!, target: nil, action: nil)
    private let menuStatus = NSMenuItem(title: "Paused", action: nil, keyEquivalent: "")
    private let menuToggle = NSMenuItem(title: "Start monitoring", action: #selector(toggleMonitoring), keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "Allow Focus File Access…", action: #selector(allowFocusFileAccess), keyEquivalent: "")
    private var imageURL: URL? {
        get { defaults.string(forKey: "focusWallpaperURL").flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: "focusWallpaperURL") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenuBar()
        makeWindow()
        Task { @MainActor in
            do {
                try await Task.detached { try LegacyCleanup.run() }.value
                // Old URL-only recovery records can refer to a stock fallback,
                // not the actual wallpaper. Keep them for diagnosis, never apply them.
                ready = true
                setStatus("Ready", error: nil)
            } catch { setStatus("Setup needs attention", error: error.localizedDescription) }
            refreshControls()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(refreshDesktop), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(refreshDesktop), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshDesktop), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        stopMonitoring()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleMonitoring() {
        if monitoring {
            stopMonitoring()
            setStatus("Paused", error: nil)
            refreshControls()
            return
        }
        guard ready, imageURL != nil else { return }
        monitoring = true
        let pollTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFocus() }
        }
        timer = pollTimer
        RunLoop.main.add(pollTimer, forMode: .common)
        checkFocus()
    }
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        monitoring = false
        presentation.stop()
    }
    @objc private func checkFocus() {
        guard monitoring else { return }
        let focused: Bool
        do { focused = try focusReader.read() }
        catch {
            setStatus("Focus access needs attention", error: error.localizedDescription)
            refreshControls()
            return
        }
        do {
            try presentation.update(focused: focused, image: imageURL)
            setStatus(focused ? "Focus on" : "Waiting for Focus", error: nil)
        } catch {
            stopMonitoring()
            setStatus("Image unavailable", error: error.localizedDescription)
        }
        refreshControls()
    }
    @objc private func refreshDesktop() {
        if monitoring {
            checkFocus()
            desktop.rebuild()
        }
    }
    @objc private func allowFocusFileAccess() {
        showWindow()
        let panel = NSOpenPanel()
        panel.title = "Allow Focus file access"
        panel.message = "Select Library/DoNotDisturb/DB. Only the Focus state file is read."
        panel.prompt = "Allow read access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = LocalFocusReader.defaultDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try focusReader.grantAccess(to: url)
            _ = try focusReader.read()
            setStatus("Ready", error: nil)
        } catch { setStatus("Focus access needs attention", error: error.localizedDescription); showDetails() }
        refreshControls()
    }
    @objc private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url, NSImage(contentsOf: source) != nil else { return }
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FocusWallpaper/Images")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
            try FileManager.default.copyItem(at: source, to: destination)
            imageURL = destination
            if monitoring { checkFocus() }
            refreshControls()
        } catch { setStatus("Couldn’t import image", error: error.localizedDescription); showDetails() }
    }
    private func setStatus(_ text: String, error: String?) {
        status.stringValue = text
        errorMessage = error
        status.toolTip = error
        menuStatus.title = text
    }
    @objc private func showDetails() {
        let alert = NSAlert()
        alert.messageText = errorMessage == nil ? "Focus Wallpaper" : status.stringValue
        alert.informativeText = errorMessage ?? "Your Focus image appears behind desktop icons while Focus is on. Your existing wallpaper settings stay untouched.\n\nClose this window to keep monitoring from the menu bar. Choose Quit from the menu bar to stop.\n\nFocus detection reads a local macOS file. If access is blocked, choose Allow Focus File Access from the menu. This undocumented format may change with macOS updates."
        showWindow()
        alert.runModal()
    }
    private func refreshControls() {
        if imageURL != lastPreviewURL {
            preview.image = imageURL.flatMap { NSImage(contentsOf: $0) }
            lastPreviewURL = imageURL
        }
        emptyPreview.isHidden = preview.image != nil
        choose.title = imageURL == nil ? "Choose…" : "Change…"
        choose.isEnabled = ready
        toggle.isEnabled = ready && imageURL != nil
        toggle.title = monitoring ? "Pause" : "Start"
        menuToggle.title = monitoring ? "Pause monitoring" : "Start monitoring"
        menuToggle.isEnabled = toggle.isEnabled
        accessItem.isEnabled = ready && !monitoring
        detail.contentTintColor = errorMessage == nil ? .secondaryLabelColor : .systemOrange
        dot.contentTintColor = errorMessage != nil ? .systemOrange : (monitoring ? .systemGreen : .tertiaryLabelColor)
        let symbol = presentation.activeImage == nil ? "moon" : "moon.fill"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Focus Wallpaper")
        statusItem.button?.toolTip = "Focus Wallpaper — \(status.stringValue)"
    }
    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuStatus.isEnabled = false
        menu.addItem(menuStatus)
        menu.addItem(.separator())
        for item in [NSMenuItem(title: "Open Focus Wallpaper", action: #selector(showWindow), keyEquivalent: ""), menuToggle, accessItem,
                     NSMenuItem(title: "Help", action: #selector(showDetails), keyEquivalent: "")] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Focus Wallpaper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }
    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 350), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Focus Wallpaper"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.moveToActiveSpace]

        let heading = NSTextField(labelWithString: "FOCUS WALLPAPER")
        heading.font = .systemFont(ofSize: 10, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        choose.target = self; choose.action = #selector(chooseWallpaper); choose.bezelStyle = .rounded
        let header = NSStackView(views: [heading, NSView(), choose])
        header.orientation = .horizontal
        header.alignment = .centerY

        let imageContainer = NSView()
        imageContainer.wantsLayer = true
        imageContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        imageContainer.layer?.cornerRadius = 12
        imageContainer.layer?.masksToBounds = true
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("Focus wallpaper preview")
        preview.translatesAutoresizingMaskIntoConstraints = false
        emptyPreview.translatesAutoresizingMaskIntoConstraints = false
        emptyPreview.textColor = .tertiaryLabelColor
        emptyPreview.font = .systemFont(ofSize: 13)
        imageContainer.addSubview(preview)
        imageContainer.addSubview(emptyPreview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            preview.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            preview.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            emptyPreview.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            emptyPreview.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
            imageContainer.heightAnchor.constraint(equalToConstant: 190)
        ])

        dot.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.isBordered = false
        detail.target = self; detail.action = #selector(showDetails)
        toggle.bezelStyle = .rounded
        toggle.controlSize = .large
        toggle.target = self; toggle.action = #selector(toggleMonitoring)
        toggle.keyEquivalent = "\r"
        let controls = NSStackView(views: [dot, status, NSView(), detail, toggle])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        let footer = NSTextField(labelWithString: "Close this window to keep running in the menu bar.")
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [header, imageContainer, controls, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            imageContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refreshControls()
        window.center()
        showWindow()
    }
}

if CommandLine.arguments.count > 1 {
    fputs("Open Focus Wallpaper to monitor Focus. Legacy wallpaper commands are retired.\n", stderr)
    exit(1)
}
private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
