import AppKit
import AVFoundation

final class MovieView: NSView {
    let movieLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        movieLayer.videoGravity = .resizeAspect
        layer?.addSublayer(movieLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        movieLayer.frame = bounds
        CATransaction.commit()
    }
}

final class SplashWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class LauncherDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let arguments = CommandLine.arguments
    var preview: Bool { arguments.contains("--preview") }
    var window: NSWindow?
    var player: AVPlayer?
    var keyMonitor: Any?
    var statusObservation: NSKeyValueObservation?
    var displayObservation: NSKeyValueObservation?
    var endObserver: NSObjectProtocol?
    var failureObserver: NSObjectProtocol?
    var watchdog: Timer?
    var finished = false
    var target: URL?
    var config = Configuration()
    var startedAt = Date()
    let bridge = WallpaperBridge()
    var bridgeTask: Task<Void, Never>?
    var statusItem: NSStatusItem?
    var statusLabel: NSMenuItem?
    var isFinale = false
    var bridgeStarting = false
    var memoryPressureSource: DispatchSourceMemoryPressure?
    var wallpaperPrepared = false
    var wallpaperWanted = true
    var handoffStarted = false
    var fallbackAttempted = false

    func log(_ event: String) {
        guard let index = arguments.firstIndex(of: "--test-report"), arguments.indices.contains(index + 1) else { return }
        let url = URL(fileURLWithPath: arguments[index + 1])
        let record = "\(String(format: "%.3f", Date().timeIntervalSince(startedAt))) \(event)\n"
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(record.utf8))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startedAt = Date()
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        do {
            let configIndex = arguments.firstIndex(of: "--config")
            let configURL = configIndex.flatMap { index in arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1]) : nil }
            do { config = try Configuration.read(from: configURL ?? Configuration.fileURL) }
            catch { config = Configuration(); log("config-fallback") }
            if !preview {
                do { target = try TargetResolver.resolve(config) }
                catch { target = try TargetResolver.resolve(Configuration()); log("target-fallback") }
            }
            if !preview { buildStatusMenu(); monitorMemoryPressure(); startBridge() }
            // Respect accessibility preferences for launch; explicit preview still plays.
            if !preview && config.respectReducedMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                finish("reduced-motion")
                return
            }
            try showMovie()
        } catch {
            if !preview, target != nil { finish("animation-unavailable") }
            else { fail(error) }
        }
    }

    func monitorMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.memoryPressureSource else { return }
            self.bridge.send(source.data.contains(.normal) ? "pressure-off" : "pressure-on")
        }
        memoryPressureSource = source
        source.resume()
    }

    func buildStatusMenu() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "龍"
        item.button?.setAccessibilityLabel("Codex 龙娘启动器")
        let menu = NSMenu()
        let label = NSMenuItem(title: config.wallpaperEnabled ? "正在准备动态壁纸…" : "动态壁纸已禁用", action: nil, keyEquivalent: "")
        menu.addItem(label)
        for (title, action) in [("播放启动动画", #selector(replay)), ("暂停壁纸", #selector(pauseWallpaper)),
                                ("启用／继续壁纸", #selector(resumeWallpaper)), ("恢复原界面", #selector(restoreWallpaper))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出龙娘启动器", action: #selector(cancel), keyEquivalent: "q").target = self
        item.menu = menu; statusItem = item; statusLabel = label
    }

    func startBridge() {
        guard config.wallpaperEnabled, let target, !bridge.isRunning, !bridgeStarting else { return }
        bridgeStarting = true
        wallpaperPrepared = false
        bridge.onEvent = { [weak self] event in
            guard let self, let kind = event["event"] as? String else { return }
            self.log("bridge-\(kind)")
            switch kind {
            case "wallpaper-prepared":
                self.wallpaperPrepared = true
                self.statusLabel?.title = "动态壁纸已准备"
                if self.finished { self.bridge.send("reveal") }
            case "status":
                if event["playing"] as? Bool == true { self.statusLabel?.title = "动态壁纸播放中" }
                else if event["betweenAppearances"] as? Bool == true { self.statusLabel?.title = "动态壁纸等待下次出现" }
            case "wallpaper-disabled": self.statusLabel?.title = "已恢复原界面"
            case "wallpaper-unavailable": self.statusLabel?.title = "当前页面暂不支持壁纸"
            case "wallpaper-waiting": self.statusLabel?.title = "正在等待 Codex 页面"
            case "codex-exited": self.statusLabel?.title = "Codex 已退出"
            case "error": self.statusLabel?.title = "壁纸组件未能启动，请重新打开启动器"
            default: break
            }
        }
        bridgeTask = Task { @MainActor in
            defer { self.bridgeStarting = false }
            do { try await bridge.start(target: target) }
            catch {
                self.statusLabel?.title = "完整退出 Codex 后，重新打开启动器以启用壁纸"
                self.log("wallpaper-not-started")
            }
        }
    }

    @objc func pauseWallpaper() { bridge.send("pause"); statusLabel?.title = "动态壁纸已暂停" }
    @objc func resumeWallpaper() {
        config.wallpaperEnabled = true
        wallpaperWanted = true
        if bridge.isRunning { bridge.send("resume") }
        else { startBridge() }
    }
    @objc func restoreWallpaper() { wallpaperWanted = false; wallpaperPrepared = false; bridge.send("disable"); statusLabel?.title = "已恢复原界面" }
    @objc func replay() {
        guard finished else { window?.makeKeyAndOrderFront(nil); return }
        cleanup(); window?.orderOut(nil)
        finished = false; isFinale = false; handoffStarted = false; fallbackAttempted = false; startedAt = Date()
        startBridge()
        NSApp.setActivationPolicy(.regular)
        do { try showMovie() } catch { fail(error) }
    }

    func buildMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        let menu = NSMenu()
        menu.addItem(withTitle: "跳过动画", action: #selector(skip), keyEquivalent: "s").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Codex Dragon", action: #selector(cancel), keyEquivalent: "q").target = self
        item.submenu = menu
        main.addItem(item)
        NSApp.mainMenu = main
    }

    func showMovie() throws {
        let url = try videoURL()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width = min(1120, visible.width * 0.86, visible.height * 0.86 * 16 / 9)
        let rect = NSRect(x: visible.midX - width / 2, y: visible.midY - width * 9 / 32,
                          width: width, height: width * 9 / 16)
        let splash = SplashWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        splash.title = "Codex Dragon"
        splash.backgroundColor = .black
        splash.isMovableByWindowBackground = true
        splash.isReleasedWhenClosed = false
        splash.hasShadow = true
        splash.level = .floating
        splash.delegate = self
        let movie = MovieView(frame: NSRect(origin: .zero, size: rect.size))
        splash.contentView = movie
        movie.layer?.cornerRadius = 16
        movie.layer?.masksToBounds = true
        let button = NSButton(title: preview ? "关闭预览  ×" : "跳过  ×", target: self, action: #selector(skip))
        button.bezelStyle = .inline
        button.contentTintColor = .white
        button.toolTip = preview ? "Esc / 空格 / 回车：关闭预览" : "Esc / 空格 / 回车：跳过并打开 Codex"
        button.setAccessibilityLabel(preview ? "关闭动画预览" : "跳过动画并打开 Codex")
        button.translatesAutoresizingMaskIntoConstraints = false
        movie.addSubview(button)
        NSLayoutConstraint.activate([button.trailingAnchor.constraint(equalTo: movie.trailingAnchor, constant: -20),
                                     button.topAnchor.constraint(equalTo: movie.topAnchor, constant: 16)])
        let item = AVPlayerItem(url: url)
        let videoPlayer = AVPlayer(playerItem: item)
        videoPlayer.isMuted = config.muted
        movie.movieLayer.player = videoPlayer
        displayObservation = movie.movieLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            DispatchQueue.main.async { if ready { self?.log("first-frame-displayed") } }
        }
        player = videoPlayer
        window = splash
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish("movie-ended") }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish("playback-failed") }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                if status == .readyToPlay { self.log("media-ready") }
                if status == .failed { self.finish("playback-failed") }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if [UInt16(53), 36, 49, 76].contains(event.keyCode) {
                self?.finish("keyboard-skip")
                return nil
            }
            return event
        }
        // A decoder failure must never leave the user trapped in a splash window.
        watchdog = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish("playback-timeout") }
        }
        splash.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        videoPlayer.play()
        log("playback-started")
    }

    @objc func skip() { finish("button-skip") }
    @objc func cancel() { cleanup(); bridge.detach(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { memoryPressureSource?.cancel(); bridge.detach() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { finish("window-close"); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if finished { replay() } else { window?.makeKeyAndOrderFront(nil) }
        return true
    }

    func cleanup() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        watchdog?.invalidate()
        statusObservation = nil
        displayObservation = nil
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = failureObserver { NotificationCenter.default.removeObserver(observer) }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        endObserver = nil; failureObserver = nil; keyMonitor = nil
    }

    func finish(_ reason: String) {
        guard !finished else { return }
        if ["movie-ended", "idle-ended"].contains(reason), !isFinale, !preview,
           wallpaperWanted, bridge.isRunning, !wallpaperPrepared, Date().timeIntervalSince(startedAt) < 90,
           let idle = Bundle.main.url(forResource: "startup-idle", withExtension: "mp4") {
            continueMovie(idle, event: "idle-started", endReason: "idle-ended")
            return
        }
        if ["movie-ended", "idle-ended"].contains(reason), !isFinale,
           let finale = Bundle.main.url(forResource: "startup-finale", withExtension: "mp4") {
            isFinale = true
            continueMovie(finale, event: "finale-started", endReason: "finale-ended")
            return
        }
        finished = true
        log(reason)
        cleanup()
        if preview { dismiss(); return }
        // Wallpaper preparation must not hold the official application hostage.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.openTarget() }
        Task { @MainActor [self] in
            await bridgeTask?.value
            openTarget()
        }
    }

    func openTarget() {
        guard !handoffStarted else { return }
        handoffStarted = true
        guard let target else { fail(LauncherError.missingApplication); return }
        bridge.send("reveal")
        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        options.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: target, configuration: options) { [weak self] application, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil, application != nil else { self.fail(error ?? LauncherError.missingApplication); return }
                self.log("handoff-success")
                self.dismiss()
            }
        }
    }

    func continueMovie(_ url: URL, event: String, endReason: String) {
        log(event)
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = failureObserver { NotificationCenter.default.removeObserver(observer) }
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(endReason) }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish("playback-failed") }
        }
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish("playback-timeout") }
        }
        player?.replaceCurrentItem(with: item)
        player?.play()
    }

    func dismiss() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduced, let view = window?.contentView {
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: -24, y: -24, width: 48, height: 48), transform: nil)
            ring.position = CGPoint(x: view.bounds.width * 0.80, y: view.bounds.height * 0.50)
            ring.strokeColor = NSColor.cyan.withAlphaComponent(0.65).cgColor
            ring.fillColor = NSColor.clear.cgColor
            ring.lineWidth = 2
            view.layer?.addSublayer(ring)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1; scale.toValue = 35; scale.duration = 0.65
            ring.add(scale, forKey: "ripple")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0 : 0.65
            window?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.window?.orderOut(nil)
                if self.preview { NSApp.terminate(nil) }
                else { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    func fail(_ error: Error) {
        log("error: \(error.localizedDescription)")
        cleanup()
        window?.orderOut(nil)
        if !preview, !fallbackAttempted, let official = try? TargetResolver.resolve(Configuration()) {
            fallbackAttempted = true
            target = official
            handoffStarted = false
            log("official-fallback")
            openTarget()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Codex Dragon 无法完成启动"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

@main
struct Launcher {
    @MainActor static func main() {
        let mediaOnly = CommandLine.arguments.contains("--diagnose-media")
        if CommandLine.arguments.contains("--diagnose") || mediaOnly {
            Task { @MainActor in
                do {
                    var report = try await mediaReport(videoURL())
                    if !mediaOnly {
                        let config = try Configuration.read()
                        let target = try TargetResolver.resolve(config)
                        report["targetApplication"] = target.path
                        report["verifiedRuntime"] = try await Task.detached { try WallpaperBridge.validateRuntime(target: target).path }.value
                    }
                    report["architecture"] = ProcessInfo.processInfo.machineArchitecture
                    report["result"] = "ok"
                    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                    exit(0)
                } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        let delegate = LauncherDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
