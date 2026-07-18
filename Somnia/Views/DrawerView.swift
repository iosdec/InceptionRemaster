import SwiftUI

// MARK: - DrawerView
// The original's navigation: a pull-down drawer above the dream map holding
// about / tutorial / more, rather than a tab bar. drawer-closed is the visible
// handle; drawer-background is the panel behind it once opened.

struct DrawerView: View {

    @State private var isOpen = false
    @State private var sheet: DrawerDestination?

    var body: some View {
        VStack(spacing: 0) {
            if isOpen {
                panel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // The handle sits at the bottom — tap it, or drag up, to open.
            Image(dream: "drawer-closed")
                .resizable()
                .scaledToFill()
                .frame(height: 30)
                .clipped()
                .overlay {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    SoundPlayer.shared.play(.drawer)
                    withAnimation(.easeInOut(duration: 0.28)) { isOpen.toggle() }
                }
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        isOpen = value.translation.height < 0   // drag up to open
                    }
                }
        )
        .sheet(item: $sheet) { destination in
            destination.view
                .presentationBackground(.black)
        }
    }

    private var panel: some View {
        ZStack {
            // scaledToFill + clipped: without clipping, the image's layout size
            // overflows and everything stacked with it drifts off-centre.
            Color.black
            Image(dream: "drawer-background")
                .resizable()
                .scaledToFill()
                .clipped()

            HStack(spacing: 0) {
                ForEach(DrawerDestination.allCases) { destination in
                    Button {
                        sheet = destination
                        withAnimation(.easeInOut(duration: 0.28)) { isOpen = false }
                    } label: {
                        Image(dream: destination.labelAsset)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 22)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 18)
        }
        .frame(height: 74)
        .clipped()
    }
}

// MARK: - Destinations

enum DrawerDestination: String, Identifiable, CaseIterable {
    case about
    case tutorial
    case settings

    var id: String { rawValue }

    /// settings has no label asset in the original — it lived under "more".
    var labelAsset: String {
        switch self {
        case .about:    return "label-about"
        case .tutorial: return "label-tutorial"
        case .settings: return "label-more"
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .about:    AboutView()
        case .tutorial: TutorialView()
        case .settings: SettingsView()
        }
    }
}
