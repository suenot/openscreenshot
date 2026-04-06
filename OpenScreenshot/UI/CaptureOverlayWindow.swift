import AppKit
import SwiftUI

class CaptureOverlayWindow: NSWindow {

    var onDismiss: (() -> Void)?
    var onCapture: (() -> Void)?

    private var selectionRect: CGRect = .zero
    private var dragStartPoint: NSPoint = .zero
    private let state = OverlayState()

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.acceptsMouseMovedEvents = true

        let view = SelectionStateView(state: state)
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = self.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        self.contentView = hosting
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKey: Bool { true }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        selectionRect = .zero
        state.selectionRect = .zero
        state.isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow
        let x = min(dragStartPoint.x, current.x)
        let y = min(dragStartPoint.y, current.y)
        let w = abs(current.x - dragStartPoint.x)
        let h = abs(current.y - dragStartPoint.y)
        // Keep in AppKit coords (bottom-left origin) for currentSelectionInScreenCoords()
        selectionRect = CGRect(x: x, y: y, width: w, height: h)
        // Flip Y for SwiftUI (top-left origin)
        let viewHeight = contentView?.bounds.height ?? frame.height
        state.selectionRect = CGRect(x: x, y: viewHeight - y - h, width: w, height: h)
        state.isDragging = true
    }

    override func mouseUp(with event: NSEvent) {
        state.isDragging = selectionRect != .zero
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onDismiss?()
        case 36, 76: // Return / Enter
            onCapture?()
        default:
            break
        }
    }

    // MARK: - Show/Hide

    func showWithCrosshair() {
        NSCursor.crosshair.set()
        self.makeKeyAndOrderFront(nil)
    }

    func hide() {
        self.orderOut(nil)
        NSCursor.arrow.set()
    }

    /// Returns the current selection in screen coordinates (points, top-left origin).
    func currentSelectionInScreenCoords() -> CGRect? {
        guard selectionRect.width > 5, selectionRect.height > 5 else { return nil }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        // Convert AppKit bottom-left window coords → CG top-left global screen coords.
        // Primary screen height is the flip reference for the global CG coordinate space.
        let primaryHeight = NSScreen.screens[0].frame.height
        let appKitGlobalY = selectionRect.minY + screen.frame.minY
        let cgY = primaryHeight - appKitGlobalY - selectionRect.height
        return CGRect(
            x: selectionRect.minX + screen.frame.minX,
            y: cgY,
            width: selectionRect.width,
            height: selectionRect.height
        )
    }
}

// MARK: - State bridge

class OverlayState: ObservableObject {
    @Published var selectionRect: CGRect = .zero
    @Published var isDragging: Bool = false
}

struct SelectionStateView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        SelectionView(
            selectionRect: Binding(
                get: { state.selectionRect },
                set: { state.selectionRect = $0 }
            ),
            isDragging: Binding(
                get: { state.isDragging },
                set: { state.isDragging = $0 }
            )
        )
    }
}
