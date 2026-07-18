import Foundation
import ZIPFoundation

// MARK: - SceneBundle
// Parses .rjz / .rj scene bundles — the same format used by the original Inception app.
// An .rjz is simply a ZIP archive containing a single .rj folder with:
//   Info.plist     — metadata (name, author, sceneId, category)
//   samples/       — .m4a audio stems
//   _main.pd       — (legacy Pure Data patch, ignored in this reimplementation)
//   abs/           — (legacy Pd abstractions, ignored)

public struct SceneInfo: Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let author: String
    public let category: SceneCategory
    public let sceneDescription: String
}

public enum SceneCategory: String, CaseIterable {
    case soundtrip
    case music
    case ambient
    case unknown

    init(rawString: String) {
        self = SceneCategory(rawValue: rawString) ?? .unknown
    }
}

public struct AudioStem: Identifiable {
    public let id: String          // filename without extension e.g. "darkhorns"
    public let url: URL
    public let role: StemRole
}

public enum StemRole: Equatable {
    case base           // always playing (ambientloop)
    case energy         // triggered by high energy (heartbeat, electronicpulse)
    case dark           // dark/tense layer (darkhorns)
    case melodic        // melodic layer (guitar, mel_icebrass)
    case rhythmic       // rhythmic layer (perc, brassperc)
    case harmonic       // harmonic layer (strings, brass)
    case unknown

    // Infer role from filename — matches patterns seen in Africa.rjz and expected in other scenes
    static func infer(from filename: String) -> StemRole {
        let name = filename.lowercased()
        if name.contains("ambient") || name.contains("loop") || name.contains("base") {
            return .base
        } else if name.contains("heartbeat") || name.contains("pulse") || name.contains("beat") {
            return .energy
        } else if name.contains("dark") || name.contains("horn") || name.contains("minor") || name.contains("ominous") {
            return .dark
        } else if name.contains("guitar") || name.contains("mel_") || name.contains("melody") || name.contains("piano") || name.contains("bell") {
            return .melodic
        } else if name.contains("perc") || name.contains("drum") || name.contains("rhythm") || name.contains("train") {
            return .rhythmic
        } else if name.contains("string") || name.contains("brass") || name.contains("choir") || name.contains("pad") {
            return .harmonic
        }
        return .unknown
    }
}

// MARK: - SceneBundle

public class SceneBundle {

    public let info: SceneInfo
    public let stems: [AudioStem]
    public let bundleURL: URL       // extracted temp directory

    private init(info: SceneInfo, stems: [AudioStem], bundleURL: URL) {
        self.info = info
        self.stems = stems
        self.bundleURL = bundleURL
    }

    deinit {
        // Clean up extracted temp directory
        try? FileManager.default.removeItem(at: bundleURL)
    }

    // MARK: - Loading

    /// Load a scene from an .rjz file (zipped) or an .rj directory.
    public static func load(from url: URL) throws -> SceneBundle {
        let ext = url.pathExtension.lowercased()

        if ext == "rjz" {
            return try loadFromZip(url: url)
        } else if ext == "rj" {
            return try loadFromDirectory(url: url)
        } else {
            throw SceneBundleError.unsupportedFormat(ext)
        }
    }

    private static func loadFromZip(url: URL) throws -> SceneBundle {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inception_scene_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: url, to: tempDir)

        let allItems = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )

        guard let rjDir = allItems.first(where: { $0.pathExtension.lowercased() == "rj" }) else {
            throw SceneBundleError.missingRjDirectory
        }

        return try loadFromDirectory(url: rjDir, tempBase: tempDir)
    }

    private static func loadFromDirectory(url: URL, tempBase: URL? = nil) throws -> SceneBundle {
        let bundleURL = tempBase ?? url

        // Parse Info.plist
        let plistURL = url.appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw SceneBundleError.missingPlist
        }

        let info = try parseInfoPlist(at: plistURL)

        // Index stems from samples/ directory
        let samplesURL = url.appendingPathComponent("samples")
        let stems = try indexStems(in: samplesURL)

        return SceneBundle(info: info, stems: stems, bundleURL: bundleURL)
    }

    // MARK: - Plist Parsing

    private static func parseInfoPlist(at url: URL) throws -> SceneInfo {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let infoDict = plist["info"] as? [String: Any] else {
            throw SceneBundleError.malformedPlist
        }

        let name = infoDict["name"] as? String ?? "Unknown"
        let author = infoDict["author"] as? String ?? "Unknown"
        let category = SceneCategory(rawString: infoDict["category"] as? String ?? "")
        let description = infoDict["description"] as? String ?? ""
        // The plist stores sceneId as a string (<string>310</string>), so `as? Int`
        // always fails — every scene would collapse to id 0. Parse the string too.
        // -1 marks a bundle with no id (e.g. the Overture ambient), which isn't a
        // maze dream and is handled separately.
        let sceneId = (infoDict["sceneId"] as? Int)
            ?? (infoDict["sceneId"] as? String).flatMap { Int($0) }
            ?? -1

        return SceneInfo(
            id: sceneId,
            name: name,
            author: author,
            category: category,
            sceneDescription: description
        )
    }

    // MARK: - Stem Indexing

    private static func indexStems(in samplesURL: URL) throws -> [AudioStem] {
        guard FileManager.default.fileExists(atPath: samplesURL.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: samplesURL,
            includingPropertiesForKeys: nil
        )

        let audioExtensions: Set<String> = ["m4a", "wav", "aif", "aiff", "mp3", "caf"]

        return files
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .map { fileURL in
                let stemId = fileURL.deletingPathExtension().lastPathComponent
                let role = StemRole.infer(from: stemId)
                return AudioStem(id: stemId, url: fileURL, role: role)
            }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Convenience

    public var baseStem: AudioStem? {
        stems.first { $0.role == .base }
            ?? stems.first { $0.id.contains("ambient") || $0.id.contains("loop") }
    }

    public func stems(for role: StemRole) -> [AudioStem] {
        stems.filter { $0.role == role }
    }
}

// MARK: - Errors

public enum SceneBundleError: LocalizedError {
    case unsupportedFormat(String)
    case missingRjDirectory
    case missingPlist
    case malformedPlist

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Unsupported scene format: .\(ext)"
        case .missingRjDirectory:         return "No .rj directory found inside archive"
        case .missingPlist:               return "Missing Info.plist in scene bundle"
        case .malformedPlist:             return "Could not parse Info.plist"
        }
    }
}
