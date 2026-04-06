import Foundation
import CoreImage
import AppKit

@MainActor
class ScreenCaptureManager {

    static let shared = ScreenCaptureManager()
    private init() {}

    // MARK: - Permission

    /// Triggers the Screen Recording permission dialog (first call only).
    func requestPermission() async -> Bool {
        // CGDisplayCreateImageForRect requires Screen Recording permission.
        // Attempt a tiny capture to trigger the system prompt.
        let display = CGMainDisplayID()
        let tiny = CGRect(x: 0, y: 0, width: 1, height: 1)
        return CGDisplayCreateImage(display, rect: tiny) != nil
    }

    // MARK: - Capture

    /// Captures `rect` (CG global coords, top-left origin, points) scaled by `preset.factor`.
    /// Returns PNG data or nil.
    func capture(rect: CGRect, preset: ScalePreset) async -> Data? {
        let displayID = displayContaining(rect: rect)

        // CGDisplayCreateImage(rect:) expects global display coordinates in points
        guard let cgImage = CGDisplayCreateImage(displayID, rect: rect) else {
            print("CGDisplayCreateImage failed — check Screen Recording permission")
            return nil
        }

        let scaled = applyScale(cgImage: cgImage, factor: preset.factor)
        return pngData(from: scaled)
    }

    // MARK: - Private

    private func displayContaining(rect: CGRect) -> CGDirectDisplayID {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        for id in displays {
            let bounds = CGDisplayBounds(id)
            if bounds.contains(rect.origin) { return id }
        }
        return CGMainDisplayID()
    }

    private func applyScale(cgImage: CGImage, factor: Double) -> CGImage {
        guard factor != 1.0 else { return cgImage }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return cgImage }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(factor, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let outputCI = filter.outputImage else { return cgImage }
        let ctx = CIContext()
        let outputRect = CGRect(
            origin: .zero,
            size: CGSize(
                width: Double(cgImage.width) * factor,
                height: Double(cgImage.height) * factor
            )
        )
        guard let result = ctx.createCGImage(outputCI, from: outputRect) else { return cgImage }
        return result
    }

    private func pngData(from cgImage: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - Clipboard

    func copyToClipboard(pngData: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }
}
