import Foundation
import CoreFoundation

let arguments = CommandLine.arguments
guard arguments.count == 4, ["bind", "restore"].contains(arguments[1]) else {
    fatalError("Usage: dock-entry bind|restore entry.app state.plist")
}
let action = arguments[1]
let entry = URL(fileURLWithPath: arguments[2], isDirectory: true)
let state = URL(fileURLWithPath: arguments[3])
let testDomain = ProcessInfo.processInfo.environment["CODEX_DRAGON_DOCK_TEST_DOMAIN"]
if let testDomain { precondition(testDomain.hasPrefix("local.codex-dragon.test.")) }
let domain = (testDomain ?? "com.apple.dock") as CFString
let key = "persistent-apps" as CFString
let identifier = "local.codex-dragon.chatgpt-entry"
let original = (CFPreferencesCopyAppValue(key, domain) as? [[String: Any]]) ?? []
func tileURL(_ tile: [String: Any]) -> URL? {
    let data = tile["tile-data"] as? [String: Any]
    let file = data?["file-data"] as? [String: Any]
    return (file?["_CFURLString"] as? String).flatMap { URL(string: $0) }
}
func owned(_ tile: [String: Any]) -> Bool {
    let data = tile["tile-data"] as? [String: Any]
    return data?["bundle-identifier"] as? String == identifier || tileURL(tile)?.path == entry.path
}
var updated = original
if action == "bind" {
    guard Bundle(url: entry)?.bundleIdentifier == identifier else { fatalError("Unexpected Dock entry identity") }
    let candidates = original.enumerated().filter { index, tile in
        if owned(tile) { return false }
        guard let url = tileURL(tile) else { return false }
        return Bundle(url: url)?.bundleIdentifier == "com.openai.codex"
    }
    if !FileManager.default.fileExists(atPath: state.path) {
        let backup: [String: Any] = ["originalPersistentApps": original,
            "replaced": candidates.map { ["index": $0.offset, "tile": $0.element] as [String: Any] }]
        try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: backup, format: .binary, options: 0).write(to: state, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: state.path)
    }
    let position = original.firstIndex(where: owned) ?? candidates.first?.offset ?? original.count
    let removing = Set(candidates.map(\.offset))
    updated = original.enumerated().filter { !removing.contains($0.offset) && !owned($0.element) }.map(\.element)
    let tile: [String: Any] = ["GUID": Int.random(in: 100000000...Int(Int32.max)), "tile-type": "file-tile",
        "tile-data": ["bundle-identifier": identifier, "file-label": "ChatGPT", "file-type": 41,
                      "file-data": ["_CFURLString": entry.absoluteString, "_CFURLStringType": 15]]]
    updated.insert(tile, at: min(position, updated.count))
} else {
    guard let data = try? Data(contentsOf: state),
          let backup = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let replaced = backup["replaced"] as? [[String: Any]] else { fatalError("No valid Dock backup") }
    updated.removeAll(where: owned)
    for item in replaced {
        guard let index = item["index"] as? Int, let tile = item["tile"] as? [String: Any] else { continue }
        // Restore only the replaced entry, preserving later edits to other apps.
        if let url = tileURL(tile), !updated.contains(where: { tileURL($0)?.path == url.path }) {
            updated.insert(tile, at: min(index, updated.count))
        }
    }
}
CFPreferencesSetAppValue(key, updated as CFArray, domain)
guard CFPreferencesAppSynchronize(domain) else { fatalError("Could not save Dock entry") }
print(action == "bind" ? "已将 ChatGPT 动画入口加入 Dock。" : "已还原 Dock 入口。")
