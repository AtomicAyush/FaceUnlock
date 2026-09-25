import AppKit
import SwiftUI
import FaceUnlockCore
import FaceUnlockVision

/// Menu-bar lifecycle: owns the status item, the watching camera, and the
/// recognition engine. It wires recognition status to the menu and nothing else —
/// there is no action wired to recognition in v1.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let camera = CameraController()
    private let embedder = FaceEmbedder.load()
    private var engine: RecognitionEngine?
    private var store: TemplateStore?

    private var isWatching = false
    private var currentStatus: RecognitionStatus = .idle

    private var enrollmentWindow: NSWindow?
    private var watchingWindow: NSWindow?
    private var watchingModel: WatchingModel?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = try? TemplateStore()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.menu = menu
        menu.delegate = self
        rebuildMenu()

        camera.onFrame = { [weak self] pixelBuffer in
            self?.engine?.process(pixelBuffer)
        }
    }

    // MARK: - Watching

    private func startWatching() {
        guard !isWatching else { return }
        Task { @MainActor in
            guard await CameraController.requestAccess() else {
                self.presentCameraDenied()
                return
            }
            do {
                if !self.camera.isConfigured { try self.camera.configure() }
            } catch {
                self.presentError("Could not start the camera", informative: "\(error)")
                return
            }

            let template = self.store?.load()
            let engine = RecognitionEngine(embedder: self.embedder, template: template)
            let model = WatchingModel(session: self.camera.session)
            engine.onStatusChange = { [weak self] status in
                DispatchQueue.main.async { self?.handleStatus(status) }
            }
            engine.onUpdate = { [weak self] update in
                DispatchQueue.main.async { self?.watchingModel?.apply(update) }
            }
            self.engine = engine
            self.watchingModel = model
            engine.begin()
            self.camera.start()
            self.isWatching = true
            self.openWatchingWindow(model: model)
            self.rebuildMenu()
        }
    }

    private func stopWatching() {
        guard isWatching else { return }
        camera.stop()
        engine?.end()
        engine = nil
        isWatching = false
        currentStatus = .idle
        if let window = watchingWindow {
            watchingWindow = nil
            window.close()
        }
        watchingModel = nil
        updateStatusIcon()
        rebuildMenu()
    }

    private func openWatchingWindow(model: WatchingModel) {
        if let window = watchingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: WatchingView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "FaceUnlock"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 380, height: 470))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        watchingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleStatus(_ status: RecognitionStatus) {
        currentStatus = status
        updateStatusIcon()
        rebuildMenu()
    }

    // MARK: - Menu

    private func updateStatusIcon() {
        let symbol: String
        switch currentStatus {
        case .recognized: symbol = "faceid"
        case .searching: symbol = "eye"
        default: symbol = "faceid"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FaceUnlock")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func statusLine() -> String {
        switch currentStatus {
        case .idle: return isWatching ? "Watching…" : "Not watching"
        case .modelMissing: return "Face model not installed"
        case .notEnrolled: return "No face enrolled"
        case .searching: return "Looking for you…"
        case .recognized(let score): return String(format: "Recognized you (%.2f)", score)
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !embedder.isAvailable {
            let hint = NSMenuItem(title: "Add the model, then enroll — see docs/MODEL.md",
                                  action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())

        let enroll = NSMenuItem(title: "Enroll Face…", action: #selector(openEnrollment), keyEquivalent: "e")
        enroll.target = self
        menu.addItem(enroll)

        let watch = NSMenuItem(title: isWatching ? "Stop Watching" : "Start Watching",
                               action: #selector(toggleWatching), keyEquivalent: "w")
        watch.target = self
        menu.addItem(watch)

        menu.addItem(.separator())

        let action = NSMenuItem(title: "On recognition: do nothing", action: nil, keyEquivalent: "")
        action.isEnabled = false
        menu.addItem(action)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit FaceUnlock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func toggleWatching() {
        isWatching ? stopWatching() : startWatching()
    }

    @objc private func openEnrollment() {
        // Enrollment drives its own camera session; pause watching to avoid two
        // sessions competing for the device.
        let wasWatching = isWatching
        if wasWatching { stopWatching() }

        if let window = enrollmentWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = EnrollmentModel(embedder: embedder, store: store)
        let view = EnrollmentView(model: model)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Enroll Your Face"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        enrollmentWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func presentCameraDenied() {
        presentError("Camera access is off",
                     informative: "Turn on the camera for FaceUnlock in System Settings → Privacy & Security → Camera.")
    }

    private func presentError(_ message: String, informative: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === enrollmentWindow {
            enrollmentWindow = nil
        } else if window === watchingWindow {
            // Closing the window is the same as stopping watching.
            watchingWindow = nil
            stopWatching()
        }
    }
}
