import SwiftUI

struct IslandView: View {
    @ObservedObject var garden: Garden
    @ObservedObject var timer: FocusTimer
    let island: Int
    var onSelectIsland: (Int) -> Void

    enum Tool: CaseIterable {
        case look, path, river, bridge, erase

        var title: String {
            switch self {
            case .look: return "Ansehen"
            case .path: return "Weg"
            case .river: return "Fluss"
            case .bridge: return "Brücke"
            case .erase: return "Radieren"
            }
        }

        var symbol: String {
            switch self {
            case .look: return "hand.raised.fill"
            case .path: return "figure.walk"
            case .river: return "water.waves"
            case .bridge: return "rectangle.split.3x1.fill"
            case .erase: return "eraser.fill"
            }
        }

        var hint: String {
            switch self {
            case .look:
                #if os(macOS)
                return "Ziehen zum Verschieben · Trackpad-Pinch zum Zoomen"
                #else
                return "Ziehen zum Verschieben · mit zwei Fingern zoomen"
                #endif
            case .path: return "Ziehe über die Insel, um einen Weg zu zeichnen"
            case .river: return "Ziehe über die Insel, um einen Fluss zu zeichnen"
            case .bridge: return "Ziehe eine Linie – z. B. quer über einen Fluss"
            case .erase: return "Tippe auf einen Weg, Fluss oder eine Brücke"
            }
        }
    }

    @State private var tool: Tool = .look
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var draft: [CGPoint] = []

    private var plants: [PlantRecord] { garden.plants(on: island) }
    private var isGrowingHere: Bool {
        island == garden.currentIsland && (timer.phase == .running || timer.phase == .paused)
    }

    private func shape() -> IslandShape {
        IslandShape(plantCount: plants.count + (isGrowingHere ? 1 : 0))
    }

    private var draftDecoration: Decoration? {
        guard draft.count >= 2 else { return nil }
        let kind: Decoration.Kind = tool == .river ? .river : tool == .bridge ? .bridge : .path
        return Decoration(id: UUID(), kind: kind, island: island, points: draft)
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let shape = shape()
                    let bob: CGFloat = tool == .look && zoom == 1 ? CGFloat(sin(t * 0.7)) * 4 : 0
                    let vp = IslandViewport(size: size, island: shape, zoom: zoom, pan: pan, bob: bob)
                    let growing = isGrowingHere
                        ? GrowingPlant(species: timer.species, seed: timer.seed, progress: timer.progress(at: timeline.date))
                        : nil
                    IslandPainter.draw(ctx, size: size, viewport: vp, shape: shape, plants: plants, growing: growing,
                                       decorations: garden.decorations(on: island), draft: draftDecoration,
                                       complete: garden.isComplete(island), time: t)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: geo.size))
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { zoom = min(6, max(1, zoomBase * $0.magnification)) }
                    .onEnded { _ in
                        zoomBase = zoom
                        pan = clampPan(pan, size: geo.size)
                        panBase = pan
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .top) { header.padding(12) }
        .overlay(alignment: .bottom) { toolbar.padding(12) }
        .onChange(of: island) { _, _ in resetView() }
    }

    // MARK: Gestures

    private func worldPoint(_ location: CGPoint, size: CGSize) -> CGPoint {
        let shape = shape()
        let vp = IslandViewport(size: size, island: shape, zoom: zoom, pan: pan)
        return shape.clamp(vp.world(location))
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch tool {
                case .look:
                    pan = clampPan(CGSize(width: panBase.width + value.translation.width,
                                          height: panBase.height + value.translation.height), size: size)
                case .path, .river:
                    let w = worldPoint(value.location, size: size)
                    if let last = draft.last, hypot(w.x - last.x, w.y - last.y) < 0.08 { return }
                    draft.append(w)
                case .bridge:
                    let w = worldPoint(value.location, size: size)
                    if draft.isEmpty { draft = [w, w] } else { draft[1] = w }
                case .erase:
                    break
                }
            }
            .onEnded { value in
                switch tool {
                case .look:
                    panBase = pan
                case .path, .river:
                    if draft.count >= 2 { garden.addDecoration(tool == .river ? .river : .path, points: draft, island: island) }
                case .bridge:
                    if draft.count == 2, hypot(draft[1].x - draft[0].x, draft[1].y - draft[0].y) > 0.3 {
                        garden.addDecoration(.bridge, points: draft, island: island)
                    }
                case .erase:
                    garden.removeDecoration(near: worldPoint(value.location, size: size), on: island, tolerance: 0.3)
                }
                draft = []
            }
    }

    private func clampPan(_ p: CGSize, size: CGSize) -> CGSize {
        let mx = size.width * (zoom - 1) / 2 + 60, my = size.height * (zoom - 1) / 2 + 60
        return CGSize(width: min(mx, max(-mx, p.width)), height: min(my, max(-my, p.height)))
    }

    private func setZoom(_ z: CGFloat) {
        zoom = min(6, max(1, z))
        zoomBase = zoom
        if zoom == 1 { pan = .zero; panBase = .zero }
    }

    private func resetView() {
        setZoom(1)
        draft = []
    }

    // MARK: Overlays

    private var header: some View {
        HStack(spacing: 10) {
            Button { onSelectIsland(island - 1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(RoundIconButtonStyle(size: 26))
                .opacity(island > 0 ? 1 : 0)
                .disabled(island == 0)
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text(Garden.islandName(island)).font(.system(size: 14, weight: .bold, design: .rounded))
                    if garden.isComplete(island) {
                        Label("vollendet", systemImage: "flag.fill")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.flag))
                    }
                }
                CapacityBar(filled: plants.count, total: Garden.islandCapacity)
            }
            Button { onSelectIsland(island + 1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(RoundIconButtonStyle(size: 26))
                .opacity(island < garden.currentIsland ? 1 : 0)
                .disabled(island >= garden.currentIsland)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private func toolButtons(showTitles: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(Tool.allCases, id: \.self) { t in
                Button { tool = t } label: {
                    Group {
                        if showTitles {
                            Label(t.title, systemImage: t.symbol).lineLimit(1).fixedSize()
                        } else {
                            Image(systemName: t.symbol)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .foregroundStyle(tool == t ? .white : Theme.ink)
                    .background(Capsule().fill(tool == t ? Palette.stem : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            Text("\(tool.title): \(tool.hint)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(.ultraThinMaterial))
            HStack(spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    toolButtons(showTitles: true)
                    toolButtons(showTitles: false)
                }
                Divider().frame(height: 18).padding(.horizontal, 4)
                Button { garden.undoDecoration(on: island) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(RoundIconButtonStyle(size: 26))
                    .help("Letzte Zeichnung zurücknehmen")
                Button { setZoom(zoom / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(RoundIconButtonStyle(size: 26))
                Button { setZoom(zoom * 1.4) } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(RoundIconButtonStyle(size: 26))
                Button { setZoom(1) } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(RoundIconButtonStyle(size: 26))
                    .help("Ansicht zurücksetzen")
            }
            .padding(5)
            .background(Capsule().fill(.ultraThinMaterial))
        }
    }
}

struct CapacityBar: View {
    let filled: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Palette.stem)
                        .frame(width: geo.size.width * CGFloat(min(filled, total)) / CGFloat(total))
                }
            }
            .frame(width: 90, height: 5)
            Text("\(min(filled, total)) / \(total)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
        }
    }
}
