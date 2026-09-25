import AppKit

// FaceUnlock is a menu-bar-only agent app: no Dock icon, no main window until the
// owner opens enrollment. Building the app this way (rather than via @main App)
// keeps the lifecycle explicit and avoids SwiftUI scene quirks in a SwiftPM
// executable. Top-level code runs on the main thread, so we assert main-actor
// isolation before touching the AppKit types that require it.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
