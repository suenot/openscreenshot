import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var overlayWindow: CaptureOverlayWindow?
    private var eventTap: CFMachPort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        requestPermissionsIfNeeded()
        // Defer hotkey setup — needs Accessibility permission granted first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupHotkey()
        }
    }

    // MARK: - Menu Bar

    private var recorderPanel: HotkeyRecorderPanel?

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "OpenScreenshot")
            button.image?.isTemplate = true
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let hotkey = HotkeyConfig.load()
        let menu = NSMenu()

        let ssItem = NSMenuItem(title: "Take Screenshot  \(hotkey.displayString)", action: #selector(openScreenshotTool), keyEquivalent: "")
        menu.addItem(ssItem)

        let hotkeyItem = NSMenuItem(title: "Set Hotkey…", action: #selector(openHotkeyRecorder), keyEquivalent: "")
        menu.addItem(hotkeyItem)

        menu.addItem(.separator())

        let scaleItem = NSMenuItem(title: "Scale", action: nil, keyEquivalent: "")
        scaleItem.tag = 100
        let scaleMenu = NSMenu()
        for preset in ScalePreset.allCases {
            let item = NSMenuItem(title: preset.displayName, action: #selector(selectScale(_:)), keyEquivalent: "")
            item.representedObject = preset.rawValue
            item.state = ScalePreset.load() == preset ? .on : .off
            scaleMenu.addItem(item)
        }
        scaleItem.submenu = scaleMenu
        menu.addItem(scaleItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = launchAtLoginEnabled ? .on : .off
        loginItem.tag = 101
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "GitHub: suenot/openscreenshot", action: #selector(openGitHub), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenScreenshot", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func openHotkeyRecorder() {
        let panel = HotkeyRecorderPanel()
        panel.onRecord = { [weak self] cfg in
            cfg.save()
            self?.reinstallEventTap()
            self?.rebuildMenu()
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.startRecording()
        recorderPanel = panel
    }

    @objc private func openScreenshotTool() {
        showCaptureUI()
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/suenot/openscreenshot")!)
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = ScalePreset(rawValue: raw) else { return }
        preset.save()
        // Update checkmarks
        sender.menu?.items.forEach { $0.state = .off }
        sender.state = .on
    }

    // MARK: - Capture UI

    func showCaptureUI() {
        // Dismiss any existing session first
        hideCaptureUI()

        let overlay = CaptureOverlayWindow()

        overlay.onDismiss = { [weak self] in self?.hideCaptureUI() }
        overlay.onCapture = { [weak self] in
            self?.performCapture(overlay: overlay)
        }

        overlay.showWithCrosshair()
        self.overlayWindow = overlay
    }

    private func hideCaptureUI() {
        overlayWindow?.hide()
        overlayWindow = nil
    }

    private func performCapture(overlay: CaptureOverlayWindow) {
        guard let rect = overlay.currentSelectionInScreenCoords() else { return }
        let preset = ScalePreset.load()
        hideCaptureUI()

        Task { @MainActor in
            guard let pngData = await ScreenCaptureManager.shared.capture(rect: rect, preset: preset) else {
                return
            }
            ScreenCaptureManager.shared.copyToClipboard(pngData: pngData)
        }
    }

    // MARK: - Global Hotkey (Cmd+Shift+6)

    private func setupHotkey() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            print("Accessibility not granted — hotkey unavailable until permission is given and app restarted")
            return
        }
        installEventTap()
    }

    private func reinstallEventTap() {
        if let old = eventTap { CGEvent.tapEnable(tap: old, enable: false) }
        eventTap = nil
        installEventTap()
    }

    private func installEventTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard type == .keyDown else { return Unmanaged.passRetained(event) }
                let cfg = HotkeyConfig.load()
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let wantFlags = CGEventFlags(rawValue: cfg.modifiers)
                // Match keycode and all required modifiers (ignore caps/numpad bits)
                let relevant = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
                if keycode == cfg.keyCode && relevant == wantFlags {
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
                    DispatchQueue.main.async { delegate.showCaptureUI() }
                    return nil // consume event
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create CGEventTap — check Accessibility permission")
            return
        }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Launch at Login

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                print("Launch at Login error: \(error)")
            }
        }
        statusItem.menu?.item(withTag: 101)?.state = launchAtLoginEnabled ? .on : .off
    }

    // MARK: - Permissions

    private func requestPermissionsIfNeeded() {
        Task {
            _ = await ScreenCaptureManager.shared.requestPermission()
        }
    }
}
