import SwiftUI

// MARK: - KickView
// Remake of KickViewController — the kick, i.e. waking up.
//
// The inverse of the dream: where the dream is a dark red vignette, the kick is
// bright and blue-white. It's what a collapsing dream lands on before the map.

/// Wrapper so a collapse reason can drive `fullScreenCover(item:)`. Each kick gets a
/// fresh id, so collapsing twice for the same reason still presents.
struct KickReason: Identifiable {
    let id = UUID()
    let text: String
}

struct KickView: View {

    /// Why the dream ended — from the original's own collapse conditions.
    let reason: String
    let onDismiss: () -> Void

    @State private var flash = false
    @State private var textIn = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Clipped to the screen — see DreamView: an unclipped .fill image
                // oversizes the stack and drags everything else off-centre.
                Image(dream: "kick-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Image(dream: "kick-overlay-tint")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(flash ? 0.15 : 0.6)

                VStack(spacing: 18) {
                    Image(dream: "kick-overlay-text")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(.horizontal, 30)
                        .opacity(textIn ? 1 : 0)

                    Text(reason)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 50)
                        .opacity(textIn ? 1 : 0)
                }

                VStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("back to the map")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(.black.opacity(0.5))
                            .tracking(3)
                            .textCase(.uppercase)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .overlay(Capsule().stroke(.black.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .opacity(textIn ? 1 : 0)
                    .padding(.bottom, 60)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.white)
        .ignoresSafeArea()
        .onAppear {
            SoundPlayer.shared.isMuted = false
            SoundPlayer.shared.play(.kick)

            // The jolt: a hard bright flash, then the text settles in.
            flash = true
            withAnimation(.easeOut(duration: 1.4)) { flash = false }
            withAnimation(.easeIn(duration: 0.8).delay(0.5)) { textIn = true }
        }
    }
}
