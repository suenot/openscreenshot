import AppKit
import SwiftUI

// MARK: - Resize Handle

enum ResizeHandle {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var movesMinX: Bool { [.topLeft, .middleLeft, .bottomLeft].contains(self) }
    var movesMaxX: Bool { [.topRight, .middleRight, .bottomRight].contains(self) }
    // AppKit: minY = bottom of screen, maxY = top
    var movesMinY: Bool { [.bottomLeft, .bottomCenter, .bottomRight].contains(self) }
    var movesMaxY: Bool { [.topLeft, .topCenter, .topRight].contains(self) }

    var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight:    return .resizeNWSE
        case .topRight, .bottomLeft:    return .resizeNESW
        case .topCenter, .bottomCenter: return .resizeUpDown
        case .middleLeft, .middleRight: return .resizeLeftRight
        }
    }
}

// MARK: - Diagonal cursor helpers

extension NSCursor {
    static var resizeNWSE: NSCursor {
        let sel = NSSelectorFromString("_windowResizeNorthWestSouthEastCursor")
        if NSCursor.responds(to: sel),
           let cursor = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return .resizeLeftRight
    }

    static var resizeNESW: NSCursor {
        let sel = NSSelectorFromString("_windowResizeNorthEastSouthWestCursor")
        if NSCursor.responds(to: sel),
           let cursor = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return .resizeLeftRight
    }
}

// MARK: - CaptureOverlayWindow

class CaptureOverlayWindow: NSWindow {

    var onDismiss: (() -> Void)?
    var onCapture: (() -> Void)?

    // AppKit coords (bottom-left origin) — used for capture
    private var selectionRect: CGRect = .zero
    private var dragStartPoint: NSPoint = .zero
    private let state = OverlayState()

    // Resize state
    private var activeHandle: ResizeHandle? = nil
    private var resizeDragStart: NSPoint = .zero
    private var resizeRectStart: CGRect = .zero
    private let handleHitRadius: CGFloat = 10
    private let minRectSize: CGFloat = 10

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
        let loc = event.locationInWindow
        if selectionRect != .zero, let handle = hitTestHandle(at: loc) {
            // Resize mode
            activeHandle = handle
            resizeDragStart = loc
            resizeRectStart = selectionRect
            state.isResizing = true
            state.isDrawingNew = false
            handle.cursor.set()
        } else {
            // New selection
            activeHandle = nil
            dragStartPoint = loc
            selectionRect = .zero
            state.selectionRect = .zero
            state.isDragging = false
            state.isDrawingNew = true
            state.isResizing = false
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow

        if let handle = activeHandle {
            // Resize existing rect
            let dx = current.x - resizeDragStart.x
            let dy = current.y - resizeDragStart.y

            var newMinX = resizeRectStart.minX
            var newMaxX = resizeRectStart.maxX
            var newMinY = resizeRectStart.minY
            var newMaxY = resizeRectStart.maxY

            if handle.movesMinX { newMinX = resizeRectStart.minX + dx }
            if handle.movesMaxX { newMaxX = resizeRectStart.maxX + dx }
            if handle.movesMinY { newMinY = resizeRectStart.minY + dy }
            if handle.movesMaxY { newMaxY = resizeRectStart.maxY + dy }

            // Enforce minimum size
            if newMaxX - newMinX < minRectSize { newMinX = newMaxX - minRectSize }
            if newMaxY - newMinY < minRectSize { newMinY = newMaxY - minRectSize }

            let newRect = CGRect(x: newMinX, y: newMinY,
                                 width: newMaxX - newMinX, height: newMaxY - newMinY)
            selectionRect = newRect
            state.selectionRect = toSwiftUICoords(newRect)
            state.isDragging = true
            state.isResizing = true
            state.isDrawingNew = false

        } else {
            // Draw new rect
            let x = min(dragStartPoint.x, current.x)
            let y = min(dragStartPoint.y, current.y)
            let w = abs(current.x - dragStartPoint.x)
            let h = abs(current.y - dragStartPoint.y)
            selectionRect = CGRect(x: x, y: y, width: w, height: h)
            state.selectionRect = toSwiftUICoords(selectionRect)
            state.isDragging = true
            state.isDrawingNew = true
            state.isResizing = false
        }
    }

    override func mouseUp(with event: NSEvent) {
        activeHandle = nil
        state.isResizing = false
        state.isDrawingNew = false
        state.isDragging = selectionRect != .zero
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = event.locationInWindow
        if selectionRect != .zero, let handle = hitTestHandle(at: loc) {
            handle.cursor.set()
        } else {
            NSCursor.crosshair.set()
        }
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

    /// Returns the current selection in CG top-left global screen coordinates.
    func currentSelectionInScreenCoords() -> CGRect? {
        guard selectionRect.width > 5, selectionRect.height > 5 else { return nil }
        let screen = NSScreen.main ?? NSScreen.screens[0]
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

    // MARK: - Private helpers

    /// Convert AppKit bottom-left rect to SwiftUI top-left rect within the window.
    private func toSwiftUICoords(_ rect: CGRect) -> CGRect {
        let viewHeight = contentView?.bounds.height ?? frame.height
        return CGRect(x: rect.minX, y: viewHeight - rect.minY - rect.height,
                      width: rect.width, height: rect.height)
    }

    /// Handle positions in AppKit coords for the current selectionRect.
    private func handlePoints(for rect: CGRect) -> [(ResizeHandle, CGPoint)] {
        return [
            (.topLeft,      CGPoint(x: rect.minX, y: rect.maxY)),
            (.topCenter,    CGPoint(x: rect.midX, y: rect.maxY)),
            (.topRight,     CGPoint(x: rect.maxX, y: rect.maxY)),
            (.middleLeft,   CGPoint(x: rect.minX, y: rect.midY)),
            (.middleRight,  CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomLeft,   CGPoint(x: rect.minX, y: rect.minY)),
            (.bottomCenter, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottomRight,  CGPoint(x: rect.maxX, y: rect.minY)),
        ]
    }

    private func hitTestHandle(at point: NSPoint) -> ResizeHandle? {
        for (handle, center) in handlePoints(for: selectionRect) {
            let dx = point.x - center.x
            let dy = point.y - center.y
            if dx*dx + dy*dy <= handleHitRadius * handleHitRadius {
                return handle
            }
        }
        return nil
    }
}

// MARK: - State bridge

class OverlayState: ObservableObject {
    @Published var selectionRect: CGRect = .zero
    @Published var isDragging: Bool = false
    @Published var isDrawingNew: Bool = false
    @Published var isResizing: Bool = false
}

struct SelectionStateView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        SelectionView(
            selectionRect: Binding(get: { state.selectionRect }, set: { state.selectionRect = $0 }),
            isDragging: Binding(get: { state.isDragging }, set: { state.isDragging = $0 }),
            isDrawingNew: Binding(get: { state.isDrawingNew }, set: { state.isDrawingNew = $0 }),
            isResizing: Binding(get: { state.isResizing }, set: { state.isResizing = $0 })
        )
    }
}
