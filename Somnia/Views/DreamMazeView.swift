import SwiftUI
import Combine

// MARK: - DreamMazeView
// Remake of ScenesMapViewController — the dream map.
//
// The original renders the map as a maze of interlocking pieces, one per dream,
// inside a UIScrollView. Locked dreams are dark; tapping one shows "How to unlock:"
// with the condition. The layout below is the original's exact tessellation,
// recovered from the minimap<sceneId> assets: 8x9 unit cells, 13 pieces, with a
// 2x2 hole at the centre of the maze.

// MARK: - Dream

public struct Dream: Identifiable, Equatable {
    public let id: Int              // sceneId, as used by the original
    public let title: String
    /// `undiscovered<id>` — shown under "How to unlock:" while locked.
    public let unlockHint: String
    /// `currenttext<id>` — what the dream is, shown once unlocked.
    public let dreamText: String
    public let cells: [GridCell]    // occupancy on the unit grid

    public static func == (a: Dream, b: Dream) -> Bool { a.id == b.id }

    /// Cells relative to the piece's own bounding box, for drawing and hit-testing
    /// inside the piece's local coordinate space.
    var localCells: [GridCell] {
        let minCol = cells.map(\.col).min() ?? 0
        let minRow = cells.map(\.row).min() ?? 0
        return cells.map { GridCell($0.col - minCol, $0.row - minRow) }
    }

    /// The piece's bounding box in points, for placing its artwork.
    func frame(cellSize: CGSize) -> CGRect {
        let cols = cells.map(\.col), rows = cells.map(\.row)
        let minCol = cols.min() ?? 0, minRow = rows.min() ?? 0
        return CGRect(
            x: CGFloat(minCol) * cellSize.width,
            y: CGFloat(minRow) * cellSize.height,
            width: CGFloat((cols.max() ?? 0) - minCol + 1) * cellSize.width,
            height: CGFloat((rows.max() ?? 0) - minRow + 1) * cellSize.height
        )
    }
}

public struct GridCell: Hashable {
    public let col: Int
    public let row: Int
    public init(_ col: Int, _ row: Int) { self.col = col; self.row = row }
}

// MARK: - Maze layout

public enum DreamMaze {
    public static let columns = 8
    public static let rows = 9

    /// Cell height / width. The original's maze is 320x468pt over 8x9 cells,
    /// i.e. 40x52pt per cell — confirmed against grid.png and the piece artwork.
    public static let cellAspect: CGFloat = 52.0 / 40.0

    /// Cell → sceneId. `nil` is the hole at the centre of the maze.
    /// Transcribed from the minimap assets; verified to tile without collisions.
    static let layout: [[Int?]] = [
        [315, 302, 302, 302, 298, 317, 301, 301],
        [315, 302, 302, 298, 298, 317, 301, 301],
        [315, 315, 314, 298, 298, 317, 297, 301],
        [315, 314, 314, 296, 296, 317, 297, 297],
        [314, 314, 314, 296, 296, 296, 297, 297],
        [316, 316, 316, nil, nil, 310, 310, 297],
        [  0, 316, 316, nil, nil, 310, 313, 313],
        [  0,   0,   0, 300, 300, 310, 313, 313],
        [  0,   0,   0, 300, 300, 300, 313, 313],
    ]

    /// Titles and locked-state hints, taken verbatim from the original's
    /// Localizable.strings (dreamTitle<id> and undiscovered<id>). Note the original
    /// keeps two texts per dream: `undiscovered` while locked, `currenttext` while
    /// the dream is playing. These are the locked ones.
    static let metadata: [(id: Int, title: String, hint: String)] = [
        (0, "Reverie Dream",
         "When you enter your dreamworld for the first time this dream will be played."),
        (296, "Action Dream",
         "To unlock this dream go back to the dream map and induce your dreamworld. Then walk or be active. But pay attention, it will not be unlocked if you put your device into sleep mode. You will be rewarded with an energetic dream which samples and sequences your dreamworld into a perfect soundtrack for moving through the city. It features the \"Mombasa\" music from the movie."),
        (297, "Sunshine Dream",
         "To unlock this dream go back to the dream map and induce your dreamworld during a sunny day and be still. You will be rewarded and surprised by a surreal dream featuring previously unreleased music from the movie."),
        (298, "Full Moon Dream",
         "Induce your dreamworld during a full moon night. This dream is only played once a month during full moon. It blends the sounds around you into a mysterious shimmering sonic texture. This dream features a previously unreleased version of Mal's theme from the Inception soundtrack."),
        (300, "Sleep Dream",
         "Come back tonight after 11pm and induce your dreamworld from the dream map when you are quiet and still. It takes the slightest sounds from your environment and weaves them into your dreams. This dream features previously unreleased soundscapes and hugely stretched musical elements from movie score."),
        (301, "Travelling Dream",
         "To unlock this dream go back to the dream map and induce your dreamworld when travelling fast. You will be rewarded by a unique version of the \"Time\" theme from the film which transforms whatever vehicle you are traveling in into a meditative instrument."),
        (302, "Quiet Dream",
         "To unlock this dream go back to the dream map and induce your dreamworld at a quiet place and be still. You will be rewarded with a vast acoustic landscape generated from your dreamworld including unreleased soundscapes from the movie."),
        (310, "Limbo Dream",
         "Entering too many dreams within dreams is unstable! You can unlock the undefined dream space of Limbo by inducing your dreamworld from the map and entering three dreams in a row. The fourth dream will take you to the shores of Limbo."),
        (313, "Still Dream",
         "To unlock this dream go back to the dream map and induce your dreamworld in a loud place and be still. You will be rewarded with the \"Dream is Collapsing\" theme featuring Johnny Marr."),
        (314, "Reward Dream",
         "Induce your dreamworld for a long time and you will discover this dream. It will occur every hour of induced dream time. This dream triggers vast sonic textures when there is a loud noise in your dreamworld and makes the sounds around you flutter gently. It is a heavenly chorus of harmonious strings and piano featuring a hugely stretched version of the Time theme from the Inception soundtrack."),
        (315, "Airport Dream",
         "To unlock this dream press the induce button while at the airport waiting for your plane. You will be rewarded with a dream that transforms the airport sounds around you into a rhythmic puzzle, replaying sounds from your past. This dream features unreleased version of the \"Radical Notion\" theme from the movie."),
        (316, "Africa Dream",
         "To unlock this dream go back to the dream map and induce your dreamworld while you are in Africa. It is a varied cinematic dream space which features the \"We Built Our Own World\" theme from the movie."),
        (317, "Shared Dream",
         "To unlock this dream you need to dream with your friends! Get at least one friend to play Inception the App on their device with you at the same location. Press the Induce button and you will enter the Shared Dream together. You will be rewarded by a unique version of the \"Run\" theme from the Inception soundtrack. Get 4 people in the dream and it will get more dramatic. If you manage to get a team of 7 people dreaming together you will unlock a special achievement!"),
    ]

    /// `currenttext<id>` — what each dream actually is, shown once unlocked.
    static let dreamTexts: [Int: String] = [
        0: "When you entered your dreamworld for the first time this dream was played. You create the world of the dream. We bring the subject into your dream. This dream twists the sounds of your dreamworld into previously unreleased music from the movie. Listen how nothing in your dreamworld sounds how it normally does. Our dreams feel real while we're in them. It's only when we wake up that we realise something was actually strange.",
        296: "Induce your dreamworld and then walk or be active. This dream will not be played if you put your device into sleep mode. Your actions in the dreamworld control the music. The longer you move, the further you progress into this dream. It cuts up and sequences the sounds around you and mixes them with the hectic rhythms of the \"Mombasa\" theme. When you have explored far into the dream you will reach a calm zone, before jumping back into the action again. It sounds beautiful when walking in the city. Try it. You can collapse this dream by staying still.",
        297: "To enter this dream induce your dreamworld during a sunny day and be still. This dream transforms your sunny day into a surreal whirling thunderstorm. Remember, our dreams feel real while we are in them. It's only when we wake up that we realize that something was actually strange. This dream features previously unreleased music from the movie. You can collapse this dream by being active or by the weather at your location changing.",
        298: "Induce your dreamworld during a full moon night. Did you realize it's a full moon today? This dream is only played once a month on a full moon night. It blends the sounds around you into a mysterious shimmering sonic texture. This dream features a previously unreleased version of Mal's theme from the Inception soundtrack. This dream will collapse when the moon is no longer full or at day break.",
        300: "Induce your dreamworld tonight after 11pm when you are still and its quiet. This dream takes the slightest sounds and infuses them into your dreams. You never really remember the beginning of a dream do you? You always wind up right in the middle of what's going on. It features previously unreleased soundscapes and hugely stretched musical elements from the movie score. This dream will collapse on day break, if you move or make noise.",
        301: "You can enter this dream by travelling fast when you induce your dreamworld. This dream listens and finds melodies to imitate. It turns whatever vehicle you are traveling in into a meditative instrument. It is a great companion on your journey. Listen to the \"Time\" theme from the soundtrack in a way you have never heard it before. If you slow down this dream will collapse.",
        302: "Induce your dreamworld and then go to a quiet place and be still to play this dream. This dream is designed for quiet places. It stretches out microscopic sounds from your dreamworld and turns them into vast acoustic landscapes. This dream includes previously unreleased soundscapes from the movie. Be careful, sounds around you will create massive ripples in your dreamworld and even the slightest movement will collapse this dream.",
        310: "Entering too many dreams within dreams is unstable! Three dreams in a row and fourth will send you to the undefined dream space of limbo. Listen how your reality is twisted wildly by the intense limbo winds. You will be locked in this dream for 3'40\".",
        313: "Induce your dreamworld in a loud place and be still to play this dream. Feel the sounds around you being absorbed into a spiral of delays interlaced with the \"Dream is Collapsing\" theme featuring Johnny Marr. You can collapse this dream by being active or going to a quiet environment.",
        314: "Induce your dreamworld for a long time and you will discover this dream. It will occur every hour of induced dream time. This dream triggers vast sonic textures when there is a loud noise in your dreamworld and makes the sounds around you flutter gently. It is a heavenly chorus of harmonious strings and piano featuring a hugely stretched version of the Time theme from the Inception soundtrack. This dream feels long whilst you are in it, but only lasts short time.",
        315: "You can enter this dream by inducing your dreamworld at the airport. It transforms the airport sounds around you into a rhythmic puzzle, replaying sounds from your past. This dream features unreleased version of the \"Radical Notion\" theme from the movie. Listen out for a secret area of the soundtrack which is triggered by airport announcements. If you leave the airport this dream will collapse.",
        316: "This dream is played to you only once and when you are in Africa. It is a varied cinematic dream space which features the \"We Built Our Own World\" theme from the movie.",
        317: "You can enter this dream by being with other dreamers when you induce your dreamworld. Get at least one friend to play Inception the App on their device with you at the same location. Press the Induce button and you will enter the Shared Dream together. You will be rewarded by a unique version of the \"Run\" theme from the Inception soundtrack. Get 4 people in the dream and it will get more dramatic. If you manage to get a team of 7 people dreaming together you will unlock a special achievement! If you dream alone this dream will collapse.",
    ]

    public static let dreams: [Dream] = metadata.map { meta in
        var cells: [GridCell] = []
        for (r, row) in layout.enumerated() {
            for (c, id) in row.enumerated() where id == meta.id {
                cells.append(GridCell(c, r))
            }
        }
        return Dream(
            id: meta.id,
            title: meta.title,
            unlockHint: meta.hint,
            dreamText: dreamTexts[meta.id] ?? meta.hint,
            cells: cells
        )
    }

    public static func dream(id: Int) -> Dream? { dreams.first { $0.id == id } }
}

// MARK: - Piece shape

/// Builds a piece outline from its cells. Each cell is inset only on edges that
/// have no neighbour in the same piece, so adjacent cells merge seamlessly and an
/// L-shaped piece renders as one L with a uniform gap against its neighbours.
struct PieceShape: Shape {
    let cells: [GridCell]
    let cellSize: CGSize
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let set = Set(cells)
        var path = Path()
        for cell in cells {
            let hasLeft   = set.contains(GridCell(cell.col - 1, cell.row))
            let hasRight  = set.contains(GridCell(cell.col + 1, cell.row))
            let hasTop    = set.contains(GridCell(cell.col, cell.row - 1))
            let hasBottom = set.contains(GridCell(cell.col, cell.row + 1))

            path.addRect(CGRect(
                x: CGFloat(cell.col) * cellSize.width + (hasLeft ? 0 : inset),
                y: CGFloat(cell.row) * cellSize.height + (hasTop ? 0 : inset),
                width: cellSize.width - (hasLeft ? 0 : inset) - (hasRight ? 0 : inset),
                height: cellSize.height - (hasTop ? 0 : inset) - (hasBottom ? 0 : inset)
            ))
        }
        return path
    }
}

// MARK: - DreamMazeView

public struct DreamMazeView: View {

    @ObservedObject var sceneController: SceneController
    @ObservedObject var audioEngine: AudioEngine

    /// sceneIds the user has unlocked.
    let unlockedIds: Set<Int>
    /// The dream currently playing, if any.
    let currentId: Int?
    let onInduce: () -> Void
    /// (dream, infinity) — inducing a specific dream from its card enters infinity mode.
    let onSelect: (Dream, Bool) -> Void
    /// Satellite view of the user's location, shown behind the maze. Nil until fixed.
    let mapImage: UIImage?
    /// Reports the maze's on-screen size so the map can be snapshotted to match.
    let onMazeSize: (CGSize) -> Void

    @State private var selectedDream: Dream?
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false

    public init(
        sceneController: SceneController,
        audioEngine: AudioEngine,
        unlockedIds: Set<Int>,
        currentId: Int?,
        mapImage: UIImage?,
        onInduce: @escaping () -> Void,
        onSelect: @escaping (Dream, Bool) -> Void,
        onMazeSize: @escaping (CGSize) -> Void
    ) {
        self.sceneController = sceneController
        self.audioEngine = audioEngine
        self.unlockedIds = unlockedIds
        self.currentId = currentId
        self.mapImage = mapImage
        self.onInduce = onInduce
        self.onSelect = onSelect
        self.onMazeSize = onMazeSize
    }

    public var body: some View {
        GeometryReader { geo in
            // The maze is a fixed 8x9 grid. Scale it to fit the space without
            // scrolling, keeping the pieces' proportions so the hatched art isn't
            // stretched — the original ran on a 320x480 screen the maze filled exactly.
            let scale = min(
                geo.size.width / CGFloat(DreamMaze.columns),
                geo.size.height / (CGFloat(DreamMaze.rows) * DreamMaze.cellAspect)
            )
            let cell = CGSize(width: scale, height: scale * DreamMaze.cellAspect)
            let mazeSize = CGSize(
                width: cell.width * CGFloat(DreamMaze.columns),
                height: cell.height * CGFloat(DreamMaze.rows)
            )

            ZStack {
                Color.black.ignoresSafeArea()
                    .onAppear { onMazeSize(mazeSize) }
                    .onChange(of: mazeSize) { _, s in onMazeSize(s) }

                ZStack(alignment: .topLeading) {
                    // A satellite view of where you actually are sits behind the
                    // maze. Unlocked tiles are translucent and reveal it; locked
                    // tiles are opaque black and hide it — the map is discovered
                    // dream by dream. Falls back to black until a location fixes.
                    Group {
                        if let map = mapImage {
                            Image(uiImage: map)
                                .resizable()
                                .scaledToFill()
                                .saturation(0.7)
                                .overlay(Color(red: 0.1, green: 0.15, blue: 0.25).opacity(0.35))
                        } else {
                            Color.black
                        }
                    }
                    .frame(width: mazeSize.width, height: mazeSize.height)
                    .clipped()

                    ForEach(DreamMaze.dreams) { dream in
                        let f = dream.frame(cellSize: cell)
                        PieceView(
                            dream: dream,
                            cellSize: cell,
                            isUnlocked: unlockedIds.contains(dream.id),
                            isPlaying: currentId == dream.id
                        )
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: f.minY)
                        // Every tile opens its info first — you never drop straight
                        // into a dream by tapping the map.
                        .onTapGesture {
                            SoundPlayer.shared.play(.tileInfo)
                            selectedDream = dream
                        }
                    }

                    // The 2x2 hole at the centre of the maze — the induce control.
                    InduceButton(action: {
                        if showWelcome {
                            hasSeenWelcome = true
                            withAnimation(.easeOut(duration: 0.3)) { showWelcome = false }
                        }
                        onInduce()
                    })
                        .frame(width: cell.width * 2, height: cell.height * 2)
                        .offset(x: cell.width * 3, y: cell.height * 5)

                    // First-launch hint, pointing down at the induce button.
                    if showWelcome {
                        WelcomeBubble()
                            .frame(width: cell.width * 3.4)
                            .offset(x: cell.width * 2.3, y: cell.height * 2.6)
                            .transition(.opacity)
                    }
                }
                // .offset is render-time only, so this ZStack's layout size is just
                // the largest piece. Anchor to topLeading or the frame below centres
                // it and the whole maze drifts down and right.
                .frame(width: mazeSize.width, height: mazeSize.height, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay {
            if let dream = selectedDream {
                DreamInfoCard(
                    dream: dream,
                    isUnlocked: unlockedIds.contains(dream.id),
                    unlock: sceneController.unlockRecords[dream.id],
                    onClose: { withAnimation(.easeOut(duration: 0.2)) { selectedDream = nil } },
                    onInduceInfinity: {
                        selectedDream = nil
                        onSelect(dream, true)   // enter in infinity mode
                    }
                )
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !hasSeenWelcome {
                withAnimation(.easeIn(duration: 0.6).delay(0.4)) { showWelcome = true }
            }
        }
    }
}

// MARK: - WelcomeBubble

/// First-launch speech bubble above the induce button.
struct WelcomeBubble: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                Text("welcome")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(.black.opacity(0.45))
                Text("Tap to induce dreamworld.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.black.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.92))
            )

            // Downward pointer toward the induce button.
            Triangle()
                .fill(Color(white: 0.92))
                .frame(width: 16, height: 8)
        }
        .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - PieceView

struct PieceView: View {
    let dream: Dream
    let cellSize: CGSize
    let isUnlocked: Bool
    let isPlaying: Bool

    // Draws only within its own bounds — the parent positions it on the grid.
    // The artwork is already cut to the piece's polyomino shape.
    var body: some View {
        Group {
            if isUnlocked {
                // Translucent state art over the satellite map behind it.
                Image(dream: isPlaying ? "red\(dream.id)" : "white\(dream.id)")
                    .resizable()
                    .interpolation(.high)
            } else {
                // Opaque black hides the map — the dream is undiscovered. Plain
                // black, as in the original; no per-tile lock icon.
                PieceShape(cells: dream.localCells, cellSize: cellSize, inset: 0.5)
                    .fill(Color.black.opacity(0.92))
            }
        }
        // Hit-test against the true polyomino, so taps in the bounding box's
        // empty corners fall through to the piece that actually owns them.
        .contentShape(PieceShape(cells: dream.localCells, cellSize: cellSize, inset: 0))
    }
}

// MARK: - InduceButton

/// The induce control — three red arrows pointing down, filling the 2x2 hole at
/// the centre of the maze. induce/induce1..3 are the original's animation frames;
/// cycling them walks the arrows downward.
struct InduceButton: View {
    let action: () -> Void
    var isEnabled: Bool = true

    @State private var frame = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        Button {
            SoundPlayer.shared.play(.induceUp)
            action()
        } label: {
            Image(dream: imageName)
                .resizable()
                .interpolation(.high)
        }
        .buttonStyle(InducePressStyle())
        .disabled(!isEnabled)
        .onReceive(timer) { _ in
            guard isEnabled else { return }
            frame = (frame + 1) % 4
        }
    }

    private var imageName: String {
        guard isEnabled else { return "induce-disabled" }
        return frame == 0 ? "induce" : "induce\(frame)"
    }
}

/// Swaps in the original's pressed artwork rather than dimming.
struct InducePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label.opacity(configuration.isPressed ? 0 : 1)
            if configuration.isPressed {
                Image(dream: "induce-pressed")
                    .resizable()
                    .interpolation(.high)
            }
        }
        .onChange(of: configuration.isPressed) { _, pressed in
            if pressed { SoundPlayer.shared.play(.induceDown) }
        }
    }
}

// MARK: - UnlockHintSheet

/// Tapping any tile opens this — a floating card over the map, as in the original.
/// Locked shows "How to unlock:"; unlocked shows what the dream is, and inducing
/// from here enters the dream in infinity mode.
struct DreamInfoCard: View {
    let dream: Dream
    let isUnlocked: Bool
    let unlock: UnlockRecord?
    let onClose: () -> Void
    let onInduceInfinity: () -> Void

    var body: some View {
        ZStack {
            // Dimmed backdrop — tap outside the card to dismiss.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            card
                .frame(maxWidth: 320)
                .padding(24)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dream.title.uppercased())
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.black.opacity(0.82))

                    if isUnlocked, let unlock {
                        Text(unlockLine(unlock))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.black.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Image(dream: "close")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isUnlocked ? "About this dream:" : "How to unlock:")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))

                    Text(isUnlocked ? dream.dreamText : dream.unlockHint)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.black.opacity(0.6))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // Bottom action — inducing a specific dream enters it in infinity mode.
            if isUnlocked {
                Button(action: onInduceInfinity) {
                    VStack(spacing: 4) {
                        Image(dream: "infinite-on")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 26)
                        Text("Induce this dream in infinity mode")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.16, green: 0.16, blue: 0.18))
                }
                .buttonStyle(.plain)
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.black.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.6), radius: 24, y: 8)
        .frame(maxHeight: 460)
    }

    private var cardBackground: some View {
        // The light panel texture from the original, behind a near-white wash so the
        // black text stays legible whatever the texture does.
        ZStack {
            Color(white: 0.93)
            Image(dream: "unlock-background")
                .resizable()
                .scaledToFill()
                .opacity(0.5)
        }
    }

    private func unlockLine(_ record: UnlockRecord) -> String {
        let df = DateFormatter()
        df.dateFormat = "MM/dd/yy"
        let date = df.string(from: record.date)
        return record.city.isEmpty ? "Unlocked on \(date)" : "Unlocked on \(date)\nin \(record.city)"
    }
}
