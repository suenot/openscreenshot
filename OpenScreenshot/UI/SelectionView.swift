import SwiftUI

struct SelectionView: View {
    @Binding var selectionRect: CGRect
    @Binding var isDragging: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isDragging {
                    Color.black.opacity(0.3)
                        .allowsHitTesting(false)
                }

                if isDragging && selectionRect != .zero {
                    // Punch a clear hole through the dim overlay
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .blendMode(.destinationOut)

                    // Selection border (dashed)
                    Rectangle()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .allowsHitTesting(false)

                    // Pixel size label
                    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                    let pw = Int(selectionRect.width * scale)
                    let ph = Int(selectionRect.height * scale)
                    Text("\(pw) × \(ph)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .position(
                            x: min(selectionRect.maxX, geo.size.width - 60),
                            y: max(selectionRect.minY - 20, 16)
                        )
                        .allowsHitTesting(false)
                }
            }
            .compositingGroup()
        }
    }
}
