import Foundation
import ScreenCaptureKit
import CoreImage
import AppKit

@MainActor
class ScreenCaptureManager {

    static let shared = ScreenCaptureManager()
    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Capture

    /// Captures `rect` (in screen points) and scales by `preset.factor`. Returns PNG data or nil.
    func capture(rect: CGRect, preset: ScalePreset) async -> Data? {
        guard let display = await primaryDisplay() else { return nil }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        config.width = Int(pixelRect.width)
        config.height = Int(pixelRect.height)
        config.sourceRect = pixelRect
        config.scalesToFit = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        do {
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            let scaled = applyScale(cgImage: cgImage, factor: preset.factor)
            return pngData(from: scaled)
        } catch {
            print("Capture error: \(error)")
            return nil
        }
    }

    // MARK: - Private

    private func primaryDisplay() async -> SCDisplay? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return content.displays.first
        } catch {
            return nil
        }
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
