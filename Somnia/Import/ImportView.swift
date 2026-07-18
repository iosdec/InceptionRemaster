import SwiftUI
import UniformTypeIdentifiers

// MARK: - ImportView
// First-run gate. The engine ships with no content, so before the map appears the
// user imports their own copy of the original app package (for artwork + sounds)
// and their own scene bundles.

struct ImportView: View {

    /// Called once enough has been imported to enter the app.
    let onReady: () -> Void

    @StateObject private var importer = IPAImporter()
    @State private var showPackagePicker = false
    @State private var showScenePicker = false
    @State private var artImported = AssetStore.shared.isImported
    @State private var scenesImported = ImportView.hasScenes

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header

                    step(
                        number: 1,
                        title: "Import the app package",
                        detail: "Somnia ships with no artwork or audio. Choose your own copy of the original app package (.ipa) and Somnia extracts what it needs — on your device, nothing uploaded.",
                        done: artImported,
                        buttonTitle: artImported ? "Re-import package" : "Choose .ipa…",
                        action: { showPackagePicker = true }
                    )

                    step(
                        number: 2,
                        title: "Add your scenes",
                        detail: "Dream scenes are RjDj-format .rjz bundles. Add the ones you own — you can add more any time.",
                        done: scenesImported,
                        buttonTitle: scenesImported ? "Add more scenes" : "Choose .rjz files…",
                        action: { showScenePicker = true }
                    )

                    statusLine

                    Button(action: onReady) {
                        Text("enter")
                            .font(.system(size: 13, weight: .light))
                            .tracking(4)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(.white.opacity(canEnter ? 0.9 : 0.25))
                            .overlay(
                                Capsule().stroke(.white.opacity(canEnter ? 0.4 : 0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEnter)

                    Text("Somnia is an independent project and is not affiliated with any rights holder. Only import content you are legally entitled to use.")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineSpacing(3)
                }
                .padding(28)
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showPackagePicker,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .zip, .zip, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    await importer.importAppPackage(from: url)
                    AssetStore.shared.clearCache()
                    artImported = AssetStore.shared.isImported
                }
            }
        }
        .fileImporter(
            isPresented: $showScenePicker,
            allowedContentTypes: [UTType(filenameExtension: "rjz") ?? .data, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importer.importScenes(from: urls)
                scenesImported = Self.hasScenes
            }
        }
    }

    private var canEnter: Bool { artImported }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("somnia")
                .font(.system(size: 30, weight: .ultraLight, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
                .tracking(8)
            Text("a reactive-audio dream engine")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(2)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch importer.phase {
        case .working(let msg):
            Label(msg, systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.red.opacity(0.7))
        case .done(let assets, let sounds):
            Label("Imported \(assets) images and \(sounds) sounds.", systemImage: "checkmark.circle")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.green.opacity(0.6))
        case .idle:
            EmptyView()
        }
    }

    private func step(number: Int, title: String, detail: String, done: Bool,
                      buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.white.opacity(done ? 0.7 : 0.4))
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(detail)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 11, weight: .light))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    static var hasScenes: Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: AssetStore.scenesDir.path)) ?? []
        return files.contains { $0.hasSuffix(".rjz") }
    }
}
