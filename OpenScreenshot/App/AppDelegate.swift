import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var overlayWindow: CaptureOverlayWindow?
    private var toolbarPanel: ToolbarPanel?
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

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "OpenScreenshot")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Take Screenshot", action: #selector(openScreenshotTool), keyEquivalent: "")
        menu.addItem(.separator())

        let scaleItem = NSMenuItem(title: "Scale: \(ScalePreset.load().displayName)", action: nil, keyEquivalent: "")
        scaleItem.tag = 100
        menu.addItem(scaleItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = launchAtLoginEnabled ? .on : .off
        loginItem.tag = 101
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenScreenshot", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func openScreenshotTool() {
        showCaptureUI()
    }

    // MARK: - Capture UI

    func showCaptureUI() {
        // Dismiss any existing session first
        hideCaptureUI()

        let overlay = CaptureOverlayWindow()
        let toolbar = ToolbarPanel()

        overlay.onDismiss = { [weak self] in self?.hideCaptureUI() }
        toolbar.onClose   = { [weak self] in self?.hideCaptureUI() }
        toolbar.onCapture = { [weak self] in
            self?.performCapture(overlay: overlay, toolbar: toolbar)
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        overlay.showWithCrosshair()
        toolbar.showCentered(on: screen)

        self.overlayWindow = overlay
        self.toolbarPanel = toolbar
    }

    private func hideCaptureUI() {
        overlayWindow?.hide()
        toolbarPanel?.hide()
        overlayWindow = nil
        toolbarPanel = nil
    }

    private func performCapture(overlay: CaptureOverlayWindow, toolbar: ToolbarPanel) {
        guard let rect = overlay.currentSelectionInScreenCoords() else { return }
        let preset = toolbar.selectedScale
        hideCaptureUI()

        Task { @MainActor in
            guard let pngData = await ScreenCaptureManager.shared.capture(rect: rect, preset: preset) else {
                return
            }
            ScreenCaptureManager.shared.copyToClipboard(pngData: pngData)
            self.updateScaleMenuItem(preset: preset)
        }
    }

    private func updateScaleMenuItem(preset: ScalePreset) {
        statusItem.menu?.item(withTag: 100)?.title = "Scale: \(preset.displayName)"
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

    private func installEventTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard type == .keyDown else { return Unmanaged.passRetained(event) }
                let flags = event.flags
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                // keycode 22 = key "6"; Cmd+Shift only
                if keycode == 22,
                   flags.contains(.maskCommand),
                   flags.contains(.maskShift),
                   !flags.contains(.maskAlternate),
                   !flags.contains(.maskControl) {
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
