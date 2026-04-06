import AppKit
import SwiftUI

class ToolbarPanel: NSPanel {

    var onClose: (() -> Void)?
    var onCapture: (() -> Void)?

    private let scaleState = ToolbarScaleState()

    var selectedScale: ScalePreset {
        get { scaleState.scale }
        set { scaleState.scale = newValue }
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false

        let view = ToolbarPanelView(
            state: scaleState,
            onClose: { [weak self] in self?.onClose?() },
            onCapture: { [weak self] in self?.onCapture?() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = self.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        self.contentView = hosting
    }

    func showCentered(on screen: NSScreen) {
        let panelW: CGFloat = 320
        let x = screen.frame.minX + (screen.visibleFrame.width - panelW) / 2
        let y = screen.frame.minY + screen.visibleFrame.minY + 20
        self.setFrameOrigin(NSPoint(x: x, y: y))
        self.orderFront(nil)
    }

    func hide() {
        self.orderOut(nil)
    }
}

class ToolbarScaleState: ObservableObject {
    @Published var scale: ScalePreset = ScalePreset.load()
}

struct ToolbarPanelView: View {
    @ObservedObject var state: ToolbarScaleState
    var onClose: () -> Void
    var onCapture: () -> Void

    var body: some View {
        ToolbarView(
            selectedScale: Binding(
                get: { state.scale },
                set: { state.scale = $0 }
            ),
            onClose: onClose,
            onCapture: onCapture
        )
        .padding(4)
    }
}
