import AppKit
import Foundation

@main
struct CoreTests {
    @MainActor static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let configurationURL = temporary.appendingPathComponent("config.json")
        let defaults = try Configuration.read(from: configurationURL)
        precondition(defaults.muted && defaults.respectReducedMotion && defaults.applicationPath == nil)
        let data = Data("{invalid-json".utf8)
        try data.write(to: configurationURL)
        do {
            _ = try Configuration.read(from: configurationURL)
            fatalError("Malformed configuration must not be silently ignored")
        } catch is DecodingError { }
        var explicit = Configuration()
        explicit.applicationPath = temporary.appendingPathComponent("missing.app").path
        do {
            _ = try TargetResolver.resolve(explicit)
            fatalError("An invalid explicit target must not launch a different application")
        } catch LauncherError.invalidApplication { }

        // A real .app fixture verifies paths with spaces and explicit selection.
        let fixture = temporary.appendingPathComponent("Application With Spaces.app")
        let executable = fixture.appendingPathComponent("Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let plist: [String: Any] = ["CFBundleExecutable": "Fixture", "CFBundleIdentifier": "local.codex-dragon.fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: fixture.appendingPathComponent("Contents/Info.plist"))
        explicit.applicationPath = fixture.path
        let resolved = try TargetResolver.resolve(explicit)
        precondition(resolved.path == fixture.path)
        try JSONEncoder().encode(explicit).write(to: configurationURL)
        let reread = try Configuration.read(from: configurationURL)
        precondition(reread.applicationPath == fixture.path)
        print("PASS: defaults, invalid config, invalid target, app paths with spaces, config round trip")
    }
}
