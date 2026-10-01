import SwiftUI

/// Island size in world units. Plants sit on a sunflower spiral, so the island grows outward from the middle
/// and earlier plants never move when new ones are added.
struct IslandShape {
    let rx: Double
    let ry: Double
    let depth: Double

    init(plantCount n: Int) {
        rx = 0.85 * sqrt(Double(max(n, 1))) + 1.1
        ry = rx * 0.42 + 0.25
        depth = rx * 0.5 + 0.4
    }

    static func position(_ index: Int) -> CGPoint {
        let r = 0.85 * sqrt(Double(index))
        let a = Double(index) * 2.399963
        return CGPoint(x: r * cos(a), y: r * sin(a) * 0.42)
    }

    /// Pulls a point back onto the grass if it lies outside the island's top ellipse.
    func clamp(_ p: CGPoint, margin: Double = 0.94) -> CGPoint {
        let k = sqrt(pow(p.x / rx, 2) + pow(p.y / ry, 2))
        return k <= margin ? p : CGPoint(x: p.x * margin / k, y: p.y * margin / k)
    }
}

/// Maps island world coordinates to view coordinates, including zoom and pan.
struct IslandViewport {
    let scale: CGFloat
    let origin: CGPoint

    init(size: CGSize, island: IslandShape, zoom: CGFloat = 1, pan: CGSize = .zero, bob: CGFloat = 0) {
        let treeTop = 1.35
        let minX = -island.rx, maxX = island.rx
        let minY = -island.ry - treeTop, maxY = island.ry + island.depth
        let fit = min(size.width * 0.84 / (maxX - minX), size.height * 0.8 / (maxY - minY))
        scale = CGFloat(fit) * zoom
        origin = CGPoint(x: size.width / 2 - CGFloat(minX + maxX) / 2 * scale + pan.width,
                         y: size.height / 2 - CGFloat(minY + maxY) / 2 * scale + pan.height + bob)
    }

    init(scale: CGFloat, origin: CGPoint) {
        self.scale = scale
        self.origin = origin
    }

    func view(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func world(_ v: CGPoint) -> CGPoint { CGPoint(x: (v.x - origin.x) / scale, y: (v.y - origin.y) / scale) }
}

struct GrowingPlant {
    let species: PlantSpecies
    let seed: Double
    let progress: Double
    /// Focus minutes the plant will hold once the session completes.
    let minutes: Int
}

/// Everything on an island beyond its plants and decorations: sky mood, animals, lighthouse and seedbed.
struct IslandScene {
    enum Lighthouse { case none, dark, lit }

    /// Local time of day (0..<24) for the sky; nil keeps the theme's plain sky.
    var hour: Double?
    /// Month (1–12) for seasonal weather; nil for none.
    var month: Int?
    var residents: Set<Resident> = []
    var lighthouse: Lighthouse = .none
    var saplings: [Sapling] = []

    static let plain = IslandScene()
}

enum IslandPainter {
    private typealias M = TreeMath

    static func draw(_ ctx: GraphicsContext, size: CGSize, viewport vp: IslandViewport, shape: IslandShape,
                     plants: [PlantRecord], growing: GrowingPlant?, decorations: [Decoration], draft: Decoration?,
                     complete: Bool, time: Double, scene: IslandScene = .plain) {
        // Dark skies already are night, so the time of day only tints light ones.
        let daylight = Daylight(hour: ctx.environment.colorScheme == .dark ? nil : scene.hour)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Palette.skyTop, Palette.skyBottom]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        LivingPainter.drawSkyMood(ctx, size: size, daylight: daylight)
        if AppTheme.current.particles == .stars {
            drawStars(ctx, size: size, time: time, opacity: 1)
        } else if daylight.night > 0.05 {
            drawStars(ctx, size: size, time: time, opacity: daylight.night)
        }
        LivingPainter.drawSunAndMoon(ctx, size: size, daylight: daylight)
        drawClouds(ctx, size: size, time: time, opacity: 0.85 * (1 - 0.55 * daylight.night))

        let s = vp.scale
        let rx = shape.rx, ry = shape.ry, depth = shape.depth
        func pt(_ x: Double, _ y: Double) -> CGPoint { vp.view(CGPoint(x: x, y: y)) }
        func ellipse(_ x: Double, _ y: Double, _ ex: Double, _ ey: Double) -> Path {
            let o = pt(x - ex, y - ey)
            return Path(ellipseIn: CGRect(x: o.x, y: o.y, width: 2 * ex * s, height: 2 * ey * s))
        }

        ctx.fill(ellipse(0, ry + depth + 0.55, rx * 0.55, 0.12), with: .color(.black.opacity(0.06)))
        var under = Path()
        under.move(to: pt(-rx, 0))
        under.addQuadCurve(to: pt(0, ry + depth), control: pt(-rx * 0.75, ry + depth * 0.95))
        under.addQuadCurve(to: pt(rx, 0), control: pt(rx * 0.75, ry + depth * 0.95))
        under.closeSubpath()
        ctx.fill(under, with: .linearGradient(Gradient(colors: [Palette.earth, Palette.earthDark]),
                                              startPoint: pt(0, 0), endPoint: pt(0, ry + depth)))
        for k in 0..<6 {
            let x = (M.rnd(7, k) - 0.5) * rx
            let y = ry * 0.55 + M.rnd(8, k) * depth * 0.45 * (1 - abs(x) / rx)
            ctx.fill(ellipse(x, y, 0.13, 0.08), with: .color(Palette.pebble.opacity(0.7)))
        }

        let top = ellipse(0, 0, rx, ry)
        ctx.fill(ellipse(0, 0.14, rx, ry), with: .color(Palette.grassDark))
        ctx.fill(top, with: .color(Palette.grass))

        let count = plants.count + (growing == nil ? 0 : 1)
        let flowerColors = [Color(hex: 0xF7B6C8), Color(hex: 0xFFE08A), Color.white, Palette.grassDark]
        for k in 0..<min(260, 10 + count * 3) {
            let rr = sqrt(M.rnd(3, k)) * 0.9
            let ang = M.rnd(4, k) * 2 * .pi
            ctx.fill(ellipse(rr * rx * cos(ang), rr * ry * sin(ang), 0.035, 0.03),
                     with: .color(flowerColors[k % flowerColors.count]))
        }

        var ground = ctx
        ground.clip(to: top)
        let all = decorations + (draft.map { [$0] } ?? [])
        for d in all where d.kind == .river { drawRiver(ground, d, vp: vp, time: time) }
        for d in all where d.kind == .path { drawPath(ground, d, vp: vp) }
        for d in all where d.kind == .bridge { drawBridge(ctx, d, vp: vp) }

        // Everything standing on the grass is drawn back to front.
        var items: [(y: Double, draw: (GraphicsContext) -> Void)] = []
        func addPlant(_ pos: CGPoint, _ species: PlantSpecies, seed: Double, minutes: Int, progress: Double) {
            let factor = sizeFactor(minutes: minutes, species: species)
            let depthFactor = 0.92 + 0.1 * (pos.y / ry)
            let unit = CGFloat(1.55 * factor * depthFactor) * s
            items.append((pos.y, { c in
                c.fill(ellipse(pos.x, pos.y, 0.3 * factor, 0.08), with: .color(Palette.grassDark.opacity(0.7)))
                PlantPainter.draw(c, species: species, base: vp.view(pos), unit: unit, progress: progress, seed: seed,
                                  time: time, ground: false, detail: unit > 40,
                                  golden: PlantSpecies.isGolden(minutes: minutes))
            }))
        }
        for (index, plant) in plants.enumerated() {
            addPlant(IslandShape.position(index), plant.species, seed: plant.seed, minutes: plant.minutes, progress: 1)
        }
        if let growing {
            addPlant(IslandShape.position(plants.count), growing.species, seed: growing.seed, minutes: growing.minutes,
                     progress: growing.progress)
        }
        items += LivingPainter.groundItems(scene, vp: vp, shape: shape, time: time, night: daylight.night)
        for item in items.sorted(by: { $0.y < $1.y }) { item.draw(ctx) }

        if complete { drawFlag(ctx, at: pt(rx * 0.78, -ry * 0.18), scale: s, time: time) }
        LivingPainter.drawAir(ctx, scene, vp: vp, shape: shape, time: time, night: daylight.night)
        if daylight.night > 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Daylight.nightColor.opacity(0.24 * daylight.night)))
        }
        LivingPainter.drawLights(ctx, scene, vp: vp, shape: shape, time: time, night: daylight.night)

        switch AppTheme.current.particles {
        case .snow: drawFalling(ctx, size: size, time: time, kind: .snow, count: 55)
        case .petals: drawFalling(ctx, size: size, time: time, kind: .petals, count: 26)
        case .stars: break
        case .none:
            // Themes without weather of their own show a light version of the real season.
            switch scene.month {
            case 3?, 4?, 5?: drawFalling(ctx, size: size, time: time, kind: .petals, count: 9)
            case 9?, 10?, 11?: drawFalling(ctx, size: size, time: time, kind: .leaves, count: 12)
            case 12?, 1?, 2?: drawFalling(ctx, size: size, time: time, kind: .snow, count: 22)
            default: break
            }
        }
    }

    static func sizeFactor(minutes: Int, species: PlantSpecies) -> Double {
        M.clamp(0.75 + Double(minutes) / 100, 0.8, 1.35) * species.islandScale
    }

    /// The plant under a point in island world coordinates; the one furthest to the front wins.
    static func plant(at point: CGPoint, in plants: [PlantRecord]) -> PlantRecord? {
        var best: (plant: PlantRecord, y: Double)?
        for (index, plant) in plants.enumerated() {
            let pos = IslandShape.position(index)
            let size = sizeFactor(minutes: plant.minutes, species: plant.species)
            let height = 0.95 * size
            let dx = (point.x - pos.x) / (0.42 * size)
            let dy = (point.y - (pos.y - height * 0.5)) / (height * 0.62)
            if dx * dx + dy * dy <= 1, best == nil || pos.y > best!.y { best = (plant, pos.y) }
        }
        return best?.plant
    }

    // MARK: Theme weather

    private static func drawStars(_ ctx: GraphicsContext, size: CGSize, time: Double, opacity: Double) {
        for i in 0..<60 {
            let x = M.rnd(11, i) * size.width
            let y = M.rnd(12, i) * size.height * 0.75
            let twinkle = time == 0 ? 0.8 : 0.45 + 0.55 * (0.5 + 0.5 * sin(time * (1 + M.rnd(13, i) * 2) + Double(i)))
            let r = 0.8 + M.rnd(14, i) * 1.4
            var c = ctx
            c.opacity = twinkle * opacity
            if i % 9 == 0 {
                c.fill(PlantPainter.star(at: CGPoint(x: x, y: y), radius: CGFloat(r * 2.6)), with: .color(Color(hex: 0xFFF3C4)))
            } else {
                c.fill(M.circle(CGFloat(x), CGFloat(y), CGFloat(r)), with: .color(.white))
            }
        }
    }

    enum Falling { case snow, petals, leaves }

    private static let leafColors: [Color] = [0xF2A93B, 0xE5646B, 0xD99A1E].map { Color(hex: $0) }

    private static func drawFalling(_ ctx: GraphicsContext, size: CGSize, time: Double, kind: Falling, count: Int) {
        let flakes = kind == .snow
        for i in 0..<count {
            let speed = (flakes ? 20 : 14) + M.rnd(21, i) * 22
            let span = size.height + 40
            let y = (M.rnd(22, i) * span + time * speed).truncatingRemainder(dividingBy: span) - 20
            let x = M.rnd(23, i) * size.width + sin(time * 0.8 + Double(i)) * (flakes ? 8 : 18)
            if flakes {
                let r = 1.2 + M.rnd(25, i) * 2
                ctx.fill(M.circle(CGFloat(x), CGFloat(y), CGFloat(r)), with: .color(.white.opacity(0.9)))
            } else {
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(time * (0.6 + M.rnd(24, i)) + Double(i)))
                c.opacity = 0.85
                let color = kind == .leaves ? leafColors[i % leafColors.count]
                    : i.isMultiple(of: 3) ? Color(hex: 0xFFFFFF) : Color(hex: 0xF7B6C8)
                c.fill(Path(ellipseIn: CGRect(x: -5, y: -3, width: 10, height: 6)), with: .color(color))
            }
        }
    }

    // MARK: Decorations

    private static func smoothPath(_ points: [CGPoint], vp: IslandViewport) -> Path {
        var path = Path()
        let v = points.map(vp.view)
        guard let first = v.first else { return path }
        path.move(to: first)
        if v.count < 3 {
            v.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 1..<(v.count - 1) {
            let mid = CGPoint(x: (v[i].x + v[i + 1].x) / 2, y: (v[i].y + v[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: v[i])
        }
        path.addLine(to: v[v.count - 1])
        return path
    }

    private static func drawRiver(_ ctx: GraphicsContext, _ d: Decoration, vp: IslandViewport, time: Double) {
        let path = smoothPath(d.points, vp: vp)
        let s = vp.scale
        ctx.stroke(path, with: .color(Palette.grassDark), style: StrokeStyle(lineWidth: 0.4 * s, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Palette.river), style: StrokeStyle(lineWidth: 0.32 * s, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Palette.riverLight), style: StrokeStyle(lineWidth: 0.13 * s, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(.white.opacity(0.75)),
                   style: StrokeStyle(lineWidth: 0.04 * s, lineCap: .round, dash: [0.07 * s, 0.45 * s], dashPhase: -CGFloat(time) * 0.35 * s))
    }

    private static func drawPath(_ ctx: GraphicsContext, _ d: Decoration, vp: IslandViewport) {
        let path = smoothPath(d.points, vp: vp)
        let s = vp.scale
        ctx.stroke(path, with: .color(Palette.pathEdge), style: StrokeStyle(lineWidth: 0.3 * s, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Palette.path), style: StrokeStyle(lineWidth: 0.24 * s, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Palette.pathStone),
                   style: StrokeStyle(lineWidth: 0.1 * s, lineCap: .round, dash: [0.001, 0.2 * s]))
    }

    private static func drawBridge(_ ctx: GraphicsContext, _ d: Decoration, vp: IslandViewport) {
        guard d.points.count == 2 else { return }
        let a = vp.view(d.points[0]), b = vp.view(d.points[1])
        let len = hypot(b.x - a.x, b.y - a.y)
        guard len > 1 else { return }
        let s = vp.scale
        var c = ctx
        c.translateBy(x: a.x, y: a.y)
        c.rotate(by: .radians(atan2(b.y - a.y, b.x - a.x)))
        let half = 0.19 * s
        c.fill(Path(roundedRect: CGRect(x: -0.04 * s, y: -half + 0.05 * s, width: len + 0.08 * s, height: half * 2), cornerRadius: 0.05 * s),
               with: .color(.black.opacity(0.12)))
        let plankW = 0.09 * s, gap = 0.03 * s
        var x: CGFloat = 0
        while x < len {
            c.fill(Path(roundedRect: CGRect(x: x, y: -half, width: min(plankW, len - x), height: half * 2), cornerRadius: 0.02 * s),
                   with: .color(Palette.wood))
            x += plankW + gap
        }
        for side in [-half, half] {
            c.fill(Path(roundedRect: CGRect(x: -0.03 * s, y: side - 0.035 * s, width: len + 0.06 * s, height: 0.07 * s), cornerRadius: 0.03 * s),
                   with: .color(Palette.woodDark))
        }
    }

    private static func drawFlag(_ ctx: GraphicsContext, at p: CGPoint, scale s: CGFloat, time: Double) {
        let poleH = 0.9 * s
        ctx.fill(Path(roundedRect: CGRect(x: p.x - 0.025 * s, y: p.y - poleH, width: 0.05 * s, height: poleH), cornerRadius: 0.02 * s),
                 with: .color(Palette.woodDark))
        let wave = CGFloat(sin(time * 3)) * 0.04 * s
        var flag = Path()
        flag.move(to: CGPoint(x: p.x + 0.02 * s, y: p.y - poleH))
        flag.addQuadCurve(to: CGPoint(x: p.x + 0.45 * s, y: p.y - poleH + 0.14 * s + wave),
                          control: CGPoint(x: p.x + 0.25 * s, y: p.y - poleH - 0.05 * s + wave))
        flag.addQuadCurve(to: CGPoint(x: p.x + 0.02 * s, y: p.y - poleH + 0.3 * s),
                          control: CGPoint(x: p.x + 0.22 * s, y: p.y - poleH + 0.3 * s - wave))
        flag.closeSubpath()
        ctx.fill(flag, with: .color(Palette.flag))
        ctx.fill(PlantPainter.star(at: CGPoint(x: p.x + 0.18 * s, y: p.y - poleH + 0.14 * s), radius: 0.06 * s),
                 with: .color(.white))
    }

    private static func drawClouds(_ ctx: GraphicsContext, size: CGSize, time: Double, opacity: Double) {
        let clouds: [(y: Double, speed: Double, scale: Double, offset: Double)] = [
            (0.12, 6, 1.0, 0.1), (0.24, 4, 0.7, 0.55), (0.08, 3, 0.55, 0.8), (0.32, 5, 0.85, 0.3),
        ]
        let span = size.width + 260
        for c in clouds {
            let x = (c.offset * span + time * c.speed).truncatingRemainder(dividingBy: span) - 130
            let y = c.y * size.height
            let r = 38 * c.scale
            for (dx, dy, k) in [(-0.9, 0.2, 0.6), (0.0, 0.0, 0.85), (0.9, 0.25, 0.55)] {
                ctx.fill(M.circle(CGFloat(x + dx * r), CGFloat(y + dy * r), CGFloat(k * r)),
                         with: .color(Palette.cloud.opacity(opacity)))
            }
        }
    }
}

/// Non-interactive island picture used for archive cards and shared images.
struct IslandThumbnail: View {
    let plants: [PlantRecord]
    let decorations: [Decoration]
    let complete: Bool
    var scene = IslandScene.plain

    var body: some View {
        Canvas { ctx, size in
            let shape = IslandShape(plantCount: plants.count)
            IslandPainter.draw(ctx, size: size, viewport: IslandViewport(size: size, island: shape), shape: shape,
                               plants: plants, growing: nil, decorations: decorations, draft: nil, complete: complete, time: 0,
                               scene: scene)
        }
    }
}
