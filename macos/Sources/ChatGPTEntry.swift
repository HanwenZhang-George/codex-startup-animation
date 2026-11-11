import AppKit

// A small, independent Dock entry. Failure of video/renderer/launcher must not
// prevent the official application from opening. Never modifies its bundle.
@MainActor
final class EntryDelegate: NSObject, NSApplicationDelegate {
    var official: URL?
    var dragon: NSRunningApplication?
    var deadline: Timer?
    var check: Timer?
    var openingFallback = false

    func log(_ event: String) {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--test-report"), arguments.indices.contains(index + 1) else { return }
        let url = URL(fileURLWithPath: arguments[index + 1])
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data("entry-\(event)\n".utf8))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            official = try TargetResolver.resolve(Configuration())
            let home = FileManager.default.homeDirectoryForCurrentUser
            let configured = Bundle.main.object(forInfoDictionaryKey: "DragonApplicationPath") as? String
            let installed = home.appendingPathComponent("Applications/Codex Dragon.app")
            let adjacent = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Codex Dragon.app")
            let launcher = configured.map { URL(fileURLWithPath: $0) }
                ?? ([installed, adjacent].first { TargetResolver.validApplication($0) } ?? installed)
            guard TargetResolver.validApplication(launcher),
                  Bundle(url: launcher)?.bundleIdentifier == "local.codex-dragon.launcher" else {
                fallback(activate: true, reason: "launcher-missing")
                return
            }
            // Independent of the main launcher's code and event loop.
            deadline = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.ensureOfficialStarted() }
            }
            check = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.dragon?.isTerminated == true { self?.fallback(activate: true, reason: "launcher-exited") }
                }
            }
            let options = NSWorkspace.OpenConfiguration()
            options.activates = true
            options.createsNewApplicationInstance = false
            let arguments = CommandLine.arguments
            if let index = arguments.firstIndex(of: "--test-report"), arguments.indices.contains(index + 1) {
                options.arguments = ["--test-report", arguments[index + 1]]
            }
            NSWorkspace.shared.openApplication(at: launcher, configuration: options) { [weak self] app, error in
                DispatchQueue.main.async {
                    guard let self, !self.openingFallback else { return }
                    if error != nil || app == nil { self.fallback(activate: true, reason: "launcher-failed"); return }
                    self.dragon = app
                    self.log("animation-opened")
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "找不到原版 ChatGPT / Codex"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func ensureOfficialStarted() {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty {
            log("official-running")
            stop()
        } else { fallback(activate: false, reason: "startup-deadline") }
    }

    func fallback(activate: Bool, reason: String) {
        guard !openingFallback, let official else { return }
        openingFallback = true
        deadline?.invalidate(); check?.invalidate()
        log("fallback-\(reason)")
        let options = NSWorkspace.OpenConfiguration()
        options.activates = activate
        options.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: official, configuration: options) { [weak self] app, error in
            DispatchQueue.main.async {
                self?.log(error == nil && app != nil ? "fallback-success" : "fallback-failed")
                self?.stop()
            }
        }
    }

    func stop() { deadline?.invalidate(); check?.invalidate(); NSApp.terminate(nil) }
}

@main
struct ChatGPTEntry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = EntryDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
