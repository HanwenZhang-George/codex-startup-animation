import AppKit
import AVFoundation

struct Configuration: Codable {
    var applicationPath: String? = nil
    var muted: Bool = true
    var respectReducedMotion: Bool = true
    var wallpaperEnabled: Bool = true

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Dragon/config.json")
    }

    static func read(from url: URL = fileURL) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
    }
}

enum LauncherError: LocalizedError {
    case invalidApplication(String)
    case missingApplication
    case missingVideo
    case invalidVideo

    var errorDescription: String? {
        switch self {
        case .invalidApplication(let path): return "指定的应用不可用：\(path)\n请在配置中指定一个有效的 .app。"
        case .missingApplication: return "没有找到 Codex。请先安装 Codex，或在配置中填写 applicationPath。"
        case .missingVideo: return "缺少启动视频。请重新安装完整的 Codex Dragon.app。"
        case .invalidVideo: return "启动视频无法解码。请重新构建或安装完整版本。"
        }
    }
}

@MainActor
enum TargetResolver {
    static func validApplication(_ url: URL) -> Bool {
        url.pathExtension == "app" && Bundle(url: url)?.executableURL.map {
            FileManager.default.isExecutableFile(atPath: $0.path)
        } == true
    }

    static func resolve(_ configuration: Configuration) throws -> URL {
        if let path = configuration.applicationPath, !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard validApplication(url), Bundle(url: url)?.bundleIdentifier != "local.codex-dragon.launcher" else {
                throw LauncherError.invalidApplication(path)
            }
            return url
        }
        // Bundle identity also finds installations renamed to ChatGPT.app.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"),
           validApplication(url) { return url }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in ["/Applications/Codex.app", "\(home)/Applications/Codex.app",
                     "/Applications/ChatGPT.app", "\(home)/Applications/ChatGPT.app"] {
            let url = URL(fileURLWithPath: path)
            if Bundle(url: url)?.bundleIdentifier == "com.openai.codex", validApplication(url) { return url }
        }
        throw LauncherError.missingApplication
    }
}

func videoURL(in bundle: Bundle = .main) throws -> URL {
    guard let url = bundle.url(forResource: "startup", withExtension: "mp4") else {
        throw LauncherError.missingVideo
    }
    return url
}

func mediaReport(_ url: URL) async throws -> [String: Any] {
    let asset = AVURLAsset(url: url)
    let playable = try await asset.load(.isPlayable)
    let duration = try await asset.load(.duration).seconds
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard playable, duration.isFinite, duration > 0, let track = tracks.first else {
        throw LauncherError.invalidVideo
    }
    let size = try await track.load(.naturalSize)
    let fps = try await track.load(.nominalFrameRate)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    let (frame, _) = try await generator.image(at: CMTime(seconds: min(4.5, duration / 2), preferredTimescale: 600))
    return ["playable": playable, "durationSeconds": duration, "width": size.width,
            "height": size.height, "fps": fps, "decodedFrameWidth": frame.width]
}
