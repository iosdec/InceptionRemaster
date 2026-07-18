import SwiftUI

// MARK: - AboutView
// Remake of AboutViewController — the info screen.

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Image(dream: "info-screen-background")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Image(dream: "info-screen-tagline")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 90)
                        .padding(.top, 40)

                    Image(dream: "info-text-1")
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    Image(dream: "info-text-2")
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    Text("Somnia — a reactive-audio dream engine. Independent and unaffiliated; it plays the scenes and content you supply. See the About and Notice in the project for details.")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                }
            }

            CloseButton { dismiss() }
        }
    }
}

// MARK: - TutorialView
// The original walks through: induce, listen, unlock, eject. Strings are its own.

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(asset: String, text: String)] = [
        ("induce",     "Tap to induce dreamworld."),
        ("tap-to-induce", "The world around you is now in your dream."),
        ("grid",       "There are many more dreams to unlock after you press induce."),
        ("eject",      "Press eject to leave your dreamworld."),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 34) {
                    Text("tutorial")
                        .font(.system(size: 22, weight: .ultraLight, design: .serif))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(5)
                        .padding(.top, 44)

                    ForEach(steps, id: \.text) { step in
                        VStack(spacing: 12) {
                            Image(dream: step.asset)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 80)

                            Text(step.text)
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 40)
                    }

                    // The original shows this warning up front — the app is built
                    // around the headset, and the mic feeds the dream.
                    Text("Warning: This app uses your headset to induce dreams through augmented sound.")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 44)
                }
            }

            CloseButton { dismiss() }
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("manualControlEnabled") private var manualControl = false
    @AppStorage("micInputEnabled") private var micEnabled = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("settings")
                        .font(.system(size: 22, weight: .ultraLight, design: .serif))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 44)

                    SettingsToggle(
                        title: "Manual control",
                        detail: "Drag inside a dream to steer its energy and mood by hand. The original is driven entirely by your surroundings — this is an addition.",
                        isOn: $manualControl
                    )

                    SettingsToggle(
                        title: "Listen to the room",
                        detail: "Use the microphone to let the sounds around you shape the dream. Audio is processed on device and never recorded.",
                        isOn: $micEnabled
                    )

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 30)
            }

            CloseButton { dismiss() }
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .tint(Color(red: 0.6, green: 0.1, blue: 0.1))

            Text(detail)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - CloseButton

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: action) {
                    Image(dream: "close")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .padding(16)
            }
            Spacer()
        }
    }
}
