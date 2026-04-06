import SwiftUI

struct SelectionView: View {
    @Binding var selectionRect: CGRect
    @Binding var isDragging: Bool
    @Binding var isDrawingNew: Bool
    @Binding var isResizing: Bool
    var scaleFactor: Double = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isDragging && selectionRect != .zero {

                    // Dashed selection border
                    Rectangle()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .allowsHitTesting(false)

                    // Size label — original and scaled
                    let backing = NSScreen.main?.backingScaleFactor ?? 2.0
                    let origW = Int(selectionRect.width * backing)
                    let origH = Int(selectionRect.height * backing)
                    let scaledW = Int(Double(origW) * scaleFactor)
                    let scaledH = Int(Double(origH) * scaleFactor)
                    let sizeText = scaleFactor == 1.0
                        ? "\(origW) × \(origH)"
                        : "\(origW) × \(origH)  →  \(scaledW) × \(scaledH)"
                    Text(sizeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .position(
                            x: min(selectionRect.maxX, geo.size.width - 80),
                            y: max(selectionRect.minY - 20, 16)
                        )
                        .allowsHitTesting(false)

                    // Resize handles — visible only when rect is settled
                    if !isDrawingNew && !isResizing {
                        ResizeHandlesView(rect: selectionRect)
                    }
                }
            }
            .compositingGroup()
        }
    }
}

// MARK: - Resize handles overlay

struct ResizeHandlesView: View {
    let rect: CGRect

    private var handlePoints: [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),  // topLeft
            CGPoint(x: rect.midX, y: rect.minY),  // topCenter
            CGPoint(x: rect.maxX, y: rect.minY),  // topRight
            CGPoint(x: rect.minX, y: rect.midY),  // middleLeft
            CGPoint(x: rect.maxX, y: rect.midY),  // middleRight
            CGPoint(x: rect.minX, y: rect.maxY),  // bottomLeft
            CGPoint(x: rect.midX, y: rect.maxY),  // bottomCenter
            CGPoint(x: rect.maxX, y: rect.maxY),  // bottomRight
        ]
    }

    var body: some View {
        ForEach(handlePoints.indices, id: \.self) { i in
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                .frame(width: 8, height: 8)
                .position(handlePoints[i])
                .allowsHitTesting(false) // NSWindow handles all mouse events
        }
    }
}
