import SwiftUI

// MARK: - AssetStore
// Serves UI artwork from disk (Application Support), not the app bundle. The app
// ships no artwork; it's extracted from the user's own copy of the original app at
// first run (see IPAImporter) and lives in the store's directory thereafter.
//
// Images are Apple CgBI-crushed PNGs, which UIImage decodes natively on-device.

@MainActor
public final class AssetStore {

    public static let shared = AssetStore()

    /// Where extracted content lives: <AppSupport>/Somnia/{Art,Sounds,Scenes}.
    /// nonisolated so the background importer can write to these paths.
    public nonisolated static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Somnia", isDirectory: true)
    }()

    public nonisolated static var artDir: URL    { root.appendingPathComponent("Art", isDirectory: true) }
    public nonisolated static var soundsDir: URL { root.appendingPathComponent("Sounds", isDirectory: true) }
    public nonisolated static var scenesDir: URL { root.appendingPathComponent("Scenes", isDirectory: true) }

    private var cache: [String: UIImage] = [:]

    private init() {
        for dir in [Self.artDir, Self.soundsDir, Self.scenesDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// True once artwork has been extracted — used to gate the import screen.
    public var isImported: Bool {
        let count = (try? FileManager.default.contentsOfDirectory(atPath: Self.artDir.path))?.count ?? 0
        return count > 0
    }

    /// Loads `name`, preferring the @2x file (scale 2) so it renders at the right
    /// size. Cached after first load. Returns nil if the asset hasn't been imported.
    public func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }

        let twoX = Self.artDir.appendingPathComponent("\(name)@2x.png")
        if let data = try? Data(contentsOf: twoX), let img = UIImage(data: data, scale: 2) {
            cache[name] = img
            return img
        }
        let oneX = Self.artDir.appendingPathComponent("\(name).png")
        if let data = try? Data(contentsOf: oneX), let img = UIImage(data: data, scale: 1) {
            cache[name] = img
            return img
        }
        return nil
    }

    public func clearCache() { cache.removeAll() }

    /// A transparent 1×1 stand-in so a missing asset renders as nothing rather than
    /// crashing or showing a broken-image glyph.
    static let placeholder: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()
}

// MARK: - Image(dream:)

public extension Image {
    /// Loads an extracted asset by name from the AssetStore, falling back to a
    /// transparent placeholder. Drop-in replacement for `Image("name")` — every
    /// `.resizable()` / `.scaledToFit()` chain keeps working, because this still
    /// returns a SwiftUI `Image`. Main-actor: it reads the store's cache, and
    /// SwiftUI view bodies (where this is used) already run on the main actor.
    @MainActor
    init(dream name: String) {
        if let ui = AssetStore.shared.image(named: name) {
            self.init(uiImage: ui)
        } else {
            self.init(uiImage: AssetStore.placeholder)
        }
    }
}
