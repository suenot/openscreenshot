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

    /// Captures `rect` (in CG global screen points, top-left origin) and scales by `preset.factor`.
    /// Returns PNG data or nil.
    func capture(rect: CGRect, preset: ScalePreset) async -> Data? {
        // NSScreen.frame uses AppKit coords (bottom-left origin).
        // rect is in CG coords (top-left origin). Convert rect origin to AppKit to find the screen.
        let primaryHeight = NSScreen.screens[0].frame.height
        let appKitOrigin = CGPoint(x: rect.origin.x, y: primaryHeight - rect.origin.y - rect.height)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitOrigin) })
                  ?? NSScreen.main
                  ?? NSScreen.screens[0]

        guard let display = await display(for: screen) else { return nil }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()

        let scale = screen.backingScaleFactor

        // SCKit sourceRect: pixel coords relative to this display, top-left origin.
        let screenCGTop = primaryHeight - screen.frame.maxY
        let relX = rect.origin.x - screen.frame.minX
        let relY = rect.origin.y - screenCGTop

        let pixelRect = CGRect(
            x: relX * scale,
            y: relY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
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

    private func display(for screen: NSScreen) async -> SCDisplay? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Match by display ID stored in NSScreen's deviceDescription
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return content.displays.first(where: { $0.displayID == screenID })
                ?? content.displays.first
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
