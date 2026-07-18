import Foundation
import Combine
import ZIPFoundation

// MARK: - IPAImporter
// Extracts the UI artwork and interaction sounds the engine needs from the user's
// own copy of the original app package (.ipa), into the AssetStore's directories.
// Nothing is uploaded or shared — extraction is entirely on-device.
//
// The original app package does NOT contain the dream scenes themselves (those were
// downloaded at runtime). Scenes are imported separately as .rjz bundles.

@MainActor
public final class IPAImporter: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case working(String)
        case done(assets: Int, sounds: Int, scenes: Int)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle

    public init() {}

    // MARK: - App package (.ipa)

    /// Unzips the package, finds Payload/<App>.app, and copies every image and audio
    /// file into the store. Copying everything (rather than a fixed list) keeps this
    /// robust to any asset the UI references now or later.
    public func importAppPackage(from pickedURL: URL) async {
        phase = .working("Reading package…")

        let needsScope = pickedURL.startAccessingSecurityScopedResource()
        defer { if needsScope { pickedURL.stopAccessingSecurityScopedResource() } }

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.extract(packageAt: pickedURL)
            }.value
            phase = .done(assets: result.assets, sounds: result.sounds, scenes: result.scenes)
            print("✅ Imported \(result.assets) art, \(result.sounds) sounds, \(result.scenes) scenes")
        } catch {
            phase = .failed(error.localizedDescription)
            print("❌ Import failed: \(error)")
        }
    }

    /// Runs off the main actor. Returns counts of what was copied.
    private nonisolated static func extract(packageAt url: URL) throws -> (assets: Int, sounds: Int, scenes: Int) {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("somnia-import-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }

        try fm.unzipItem(at: url, to: temp)

        // Payload/<Something>.app
        let payload = temp.appendingPathComponent("Payload", isDirectory: true)
        guard let appDir = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw ImportError.notAnAppPackage
        }

        try fm.createDirectory(at: AssetStore.artDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: AssetStore.soundsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: AssetStore.scenesDir, withIntermediateDirectories: true)

        var assets = 0, sounds = 0
        let entries = try fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)
        for file in entries {
            let ext = file.pathExtension.lowercased()
            let dest: URL
            switch ext {
            case "png":
                dest = AssetStore.artDir.appendingPathComponent(file.lastPathComponent); assets += 1
            case "m4a", "wav", "caf", "aif", "aiff":
                dest = AssetStore.soundsDir.appendingPathComponent(file.lastPathComponent); sounds += 1
            default:
                continue
            }
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: file, to: dest)
        }

        // Scenes ship inside the package after all: compressed .rjz bundles in
        // rjdj_scenes/, and uncompressed .rj folders in scenes/. Pull both — no
        // manual picking needed.
        let scenes = copyScenes(from: appDir, using: fm)

        guard assets > 0 else { throw ImportError.noAssetsFound }
        return (assets, sounds, scenes)
    }

    /// Copies every .rjz bundle and .rj folder found under the app's scene
    /// directories into the store. Returns how many were copied.
    private nonisolated static func copyScenes(from appDir: URL, using fm: FileManager) -> Int {
        var copied = 0
        for sub in ["rjdj_scenes", "scenes"] {
            let dir = appDir.appendingPathComponent(sub, isDirectory: true)
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items where ["rjz", "rj"].contains(item.pathExtension.lowercased()) {
                let dest = AssetStore.scenesDir.appendingPathComponent(item.lastPathComponent)
                try? fm.removeItem(at: dest)
                do {
                    try fm.copyItem(at: item, to: dest)   // copies whole .rj folders too
                    copied += 1
                } catch {
                    print("⚠️ Could not copy scene \(item.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return copied
    }

    // MARK: - Scenes (.rjz)

    /// Copies picked .rjz scene bundles into the store. Returns how many landed.
    @discardableResult
    public func importScenes(from urls: [URL]) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: AssetStore.scenesDir, withIntermediateDirectories: true)

        var copied = 0
        for url in urls where url.pathExtension.lowercased() == "rjz" {
            let scope = url.startAccessingSecurityScopedResource()
            defer { if scope { url.stopAccessingSecurityScopedResource() } }

            let dest = AssetStore.scenesDir.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            do {
                try fm.copyItem(at: url, to: dest)
                copied += 1
            } catch {
                print("⚠️ Could not import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        print("✅ Imported \(copied) scene(s)")
        return copied
    }

    public enum ImportError: LocalizedError {
        case notAnAppPackage
        case noAssetsFound

        public var errorDescription: String? {
            switch self {
            case .notAnAppPackage:
                return "That doesn't look like an app package — no Payload/*.app inside."
            case .noAssetsFound:
                return "No artwork found in that package."
            }
        }
    }
}
