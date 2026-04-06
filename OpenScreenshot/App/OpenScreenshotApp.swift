import SwiftUI

@main
struct OpenScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar only app — no windows
        Settings { EmptyView() }
    }
}
