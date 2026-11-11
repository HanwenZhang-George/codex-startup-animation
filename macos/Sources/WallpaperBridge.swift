import AppKit

enum BridgeError: LocalizedError {
    case runtimeUnavailable
    case applicationAlreadyRunning
    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: return "当前客户端没有可验证的运行组件，已保留普通启动。"
        case .applicationAlreadyRunning: return "Codex 已经从普通入口运行。请保存工作并完整退出 Codex，再打开此启动器以启用动态壁纸。"
        }
    }
}

@MainActor
final class WallpaperBridge {
    var onEvent: (([String: Any]) -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var lineBuffer = Data()
    var isRunning: Bool { process?.isRunning == true }

    nonisolated static func validateRuntime(target: URL) throws -> URL {
        guard Bundle(url: target)?.bundleIdentifier == "com.openai.codex" else { throw BridgeError.runtimeUnavailable }
        let runtime = target.appendingPathComponent("Contents/Resources/cua_node/bin/node")
        guard FileManager.default.isExecutableFile(atPath: runtime.path) else { throw BridgeError.runtimeUnavailable }
        for (url, identity) in [(target, " and identifier \"com.openai.codex\""), (runtime, "")] {
            let verification = Process()
            verification.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            verification.arguments = ["--verify", "--strict", "--test-requirement",
                "=anchor apple generic and certificate leaf[subject.OU] = \"2DC432GLL2\"\(identity)", url.path]
            verification.standardOutput = FileHandle.nullDevice
            verification.standardError = FileHandle.nullDevice
            let ended = DispatchSemaphore(value: 0)
            verification.terminationHandler = { _ in ended.signal() }
            try verification.run()
            guard ended.wait(timeout: .now() + 3) == .success else {
                verification.terminate()
                throw BridgeError.runtimeUnavailable
            }
            guard verification.terminationStatus == 0 else { throw BridgeError.runtimeUnavailable }
        }
        return runtime
    }

    func start(target: URL) async throws {
        let runtime = try await Task.detached { try Self.validateRuntime(target: target) }.value
        if let identifier = Bundle(url: target)?.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty {
            throw BridgeError.applicationAlreadyRunning
        }
        guard let helper = Bundle.main.url(forResource: "bridge", withExtension: "mjs"),
              let executable = Bundle(url: target)?.executableURL else { throw BridgeError.runtimeUnavailable }
        let child = Process()
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        child.executableURL = runtime
        child.arguments = [helper.path, executable.path]
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = FileHandle.nullDevice
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.receive(data) }
        }
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.onEvent?(["event": "bridge-exited"]) }
        }
        self.input = stdinPipe; self.output = stdoutPipe; self.process = child
        try child.run()
    }

    private func receive(_ data: Data) {
        guard lineBuffer.count + data.count <= 65536 else { lineBuffer.removeAll(); return }
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 10) {
            let record = lineBuffer.prefix(upTo: newline)
            lineBuffer.removeSubrange(...newline)
            if let event = try? JSONSerialization.jsonObject(with: record) as? [String: Any] { onEvent?(event) }
        }
    }

    func send(_ command: String) {
        guard ["reveal", "pause", "resume", "disable", "pressure-on", "pressure-off"].contains(command), isRunning else { return }
        let data = Data("{\"command\":\"\(command)\"}\n".utf8)
        try? input?.fileHandleForWriting.write(contentsOf: data)
    }

    func detach() {
        send("disable")
        try? input?.fileHandleForWriting.close()
        // The helper restores styles and holds the private pipe until Codex quits.
    }
}
