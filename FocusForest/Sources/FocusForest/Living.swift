import SwiftUI

/// How far the real time of day tints the sky: `night` runs from 0 (day) to 1 (night), `warm` peaks at dawn and dusk.
struct Daylight {
    static let nightColor = Color(hex: 0x10163A)

    let hour: Double?
    let night: Double
    let warm: Double

    init(hour: Double?) {
        self.hour = hour
        guard let h = hour else {
            night = 0
            warm = 0
            return
        }
        night = h < 5 || h >= 21 ? 1 : h < 7 ? 1 - (h - 5) / 2 : h >= 19 ? (h - 19) / 2 : 0
        warm = max(0, 1 - abs(h - 6) / 1.5, 1 - abs(h - 19.5) / 1.5)
    }

    static func hour(of date: Date) -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
    }
}

/// Draws what makes the island feel alive: sun and moon, animals, the lighthouse and the seedbed for saplings.
enum LivingPainter {
    private typealias M = TreeMath

    private static let cream = Color(hex: 0xF7EEDD)
    private static let fox = Color(hex: 0xE8894A)
    private static let birdBlue = Color(hex: 0x7FB2E5)
    private static let birdDark = Color(hex: 0x5E97D1)
    private static let beak = Color(hex: 0xF2A93B)
    private static let red = Color(hex: 0xE8645A)
    private static let lamp = Color(hex: 0xFFE08A)
    private static let glow = Color(hex: 0xFFF3A0)
    private static let wingColors: [Color] = [0xF7B6C8, 0xFFD45C].map { Color(hex: $0) }

    private static func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        for (i, p) in points.enumerated() {
            i == 0 ? path.move(to: CGPoint(x: p.0, y: p.1)) : path.addLine(to: CGPoint(x: p.0, y: p.1))
        }
        path.closeSubpath()
        return path
    }

    // MARK: Sky

    static func drawSkyMood(_ ctx: GraphicsContext, size: CGSize, daylight: Daylight) {
        let rect = Path(CGRect(origin: .zero, size: size))
        if daylight.warm > 0 {
            ctx.fill(rect, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xFFAA6E).opacity(0), Color(hex: 0xFFAA6E).opacity(0.5 * daylight.warm)]),
                startPoint: CGPoint(x: 0, y: size.height * 0.15), endPoint: CGPoint(x: 0, y: size.height)))
        }
        if daylight.night > 0 {
            ctx.fill(rect, with: .color(Daylight.nightColor.opacity(0.66 * daylight.night)))
        }
    }

    static func drawSunAndMoon(_ ctx: GraphicsContext, size: CGSize, daylight: Daylight) {
        guard let h = daylight.hour else { return }
        func position(_ t: Double) -> CGPoint {
            CGPoint(x: size.width * (0.14 + 0.72 * t), y: size.height * (0.4 - 0.28 * sin(.pi * t)))
        }
        if daylight.night < 1 {
            let p = position(M.clamp((h - 6) / 14))
            var c = ctx
            c.opacity = 1 - daylight.night
            c.fill(M.circle(p.x, p.y, 34), with: .radialGradient(
                Gradient(colors: [lamp.opacity(0.5), lamp.opacity(0)]), center: p, startRadius: 8, endRadius: 34))
            c.fill(M.circle(p.x, p.y, 15), with: .color(lamp))
        }
        if daylight.night > 0 {
            let p = position(M.clamp(((h < 12 ? h + 24 : h) - 19) / 12))
            var c = ctx
            c.opacity = daylight.night
            c.fill(M.circle(p.x, p.y, 30), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)]), center: p, startRadius: 8, endRadius: 30))
            c.fill(M.circle(p.x, p.y, 13), with: .color(Color(hex: 0xF4F1DE)))
            c.fill(M.circle(p.x - 4, p.y - 3, 3), with: .color(Color(hex: 0xDDD8BE)))
            c.fill(M.circle(p.x + 4, p.y + 4, 2), with: .color(Color(hex: 0xDDD8BE)))
        }
    }

    // MARK: On the grass

    private static func bunnySpot(_ shape: IslandShape, time: Double) -> (pos: CGPoint, dir: CGFloat) {
        let cycle = (time * 0.07).truncatingRemainder(dividingBy: 2)
        let u = M.smooth(0, 1, cycle < 1 ? cycle : 2 - cycle)
        let a = CGPoint(x: -0.70 * shape.rx, y: 0.50 * shape.ry), b = CGPoint(x: -0.36 * shape.rx, y: 0.78 * shape.ry)
        return (CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u), cycle < 1 ? 1 : -1)
    }

    private static func lighthouseSpot(_ shape: IslandShape) -> CGPoint {
        CGPoint(x: -0.80 * shape.rx, y: -0.16 * shape.ry)
    }

    /// Where each waiting sapling stands: a row along the front edge of the island.
    static func seedbed(_ saplings: [Sapling], shape: IslandShape) -> [(sapling: Sapling, pos: CGPoint)] {
        let spacing = min(0.5, shape.rx * 1.2 / Double(max(saplings.count, 1)))
        return saplings.enumerated().map { index, sapling in
            let x = (Double(index) - Double(saplings.count - 1) / 2) * spacing
            let y = shape.ry * 0.84 * sqrt(max(0, 1 - pow(x / shape.rx, 2)))
            return (sapling, CGPoint(x: x, y: y))
        }
    }

    static func groundItems(_ scene: IslandScene, vp: IslandViewport, shape: IslandShape, time: Double,
                            night: Double) -> [(y: Double, draw: (GraphicsContext) -> Void)] {
        var items: [(y: Double, draw: (GraphicsContext) -> Void)] = []
        let s = vp.scale

        for (sapling, pos) in seedbed(scene.saplings, shape: shape) {
            let unit = CGFloat(1.3 * sapling.species.islandScale) * s
            items.append((pos.y, { c in
                PlantPainter.draw(c, species: sapling.species, base: vp.view(pos), unit: unit, progress: sapling.progress,
                                  seed: sapling.seed, time: time, ground: true, detail: unit > 40)
            }))
        }
        if scene.lighthouse != .none {
            let pos = lighthouseSpot(shape)
            items.append((pos.y, { c in drawLighthouse(c, at: vp.view(pos), s: s, lit: scene.lighthouse == .lit) }))
        }
        if scene.residents.contains(.bunny) {
            let spot = bunnySpot(shape, time: time)
            items.append((spot.pos.y, { c in drawBunny(c, at: vp.view(spot.pos), s: s, dir: spot.dir, time: time) }))
        }
        if scene.residents.contains(.fox) {
            let pos = CGPoint(x: 0.56 * shape.rx, y: 0.70 * shape.ry)
            items.append((pos.y, { c in drawFox(c, at: vp.view(pos), s: s, time: time, asleep: night > 0.6) }))
        }
        return items
    }

    private static func drawBunny(_ ctx: GraphicsContext, at p: CGPoint, s: CGFloat, dir: CGFloat, time: Double) {
        ctx.fill(oval(p.x, p.y, 0.2 * s, 0.05 * s), with: .color(Palette.grassDark.opacity(0.7)))
        var c = ctx
        c.translateBy(x: p.x, y: p.y - (time == 0 ? 0 : CGFloat(abs(sin(time * 5))) * 0.07 * s))
        c.scaleBy(x: dir * s, y: s)
        c.fill(M.circle(-0.1, -0.07, 0.035), with: .color(.white))
        c.fill(oval(0, -0.075, 0.2, 0.14), with: .color(cream))
        for x: CGFloat in [0.07, 0.108] {
            c.fill(oval(x, -0.26, 0.036, 0.12), with: .color(cream))
            c.fill(oval(x, -0.26, 0.016, 0.08), with: .color(Palette.blush.opacity(0.8)))
        }
        c.fill(M.circle(0.09, -0.16, 0.062), with: .color(cream))
        c.fill(M.circle(0.112, -0.166, 0.01), with: .color(Palette.face))
        c.fill(M.circle(0.128, -0.14, 0.014), with: .color(Palette.blush.opacity(0.7)))
    }

    private static func drawFox(_ ctx: GraphicsContext, at p: CGPoint, s: CGFloat, time: Double, asleep: Bool) {
        ctx.fill(oval(p.x, p.y, 0.26 * s, 0.06 * s), with: .color(Palette.grassDark.opacity(0.7)))
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        // Sits on the right side of the island and looks towards its middle.
        c.scaleBy(x: -s, y: s)
        var tail = c
        tail.translateBy(x: -0.07, y: -0.05)
        tail.rotate(by: .radians(time == 0 ? 0 : sin(time * 2) * 0.22))
        tail.fill(oval(-0.08, -0.02, 0.2, 0.09), with: .color(fox))
        tail.fill(M.circle(-0.16, -0.02, 0.038), with: .color(cream))
        c.fill(oval(0, -0.11, 0.16, 0.22), with: .color(fox))
        c.fill(oval(0.02, -0.09, 0.08, 0.14), with: .color(cream))
        c.fill(polygon([(-0.04, -0.3), (-0.022, -0.39), (0.012, -0.32)]), with: .color(fox))
        c.fill(polygon([(0.04, -0.32), (0.076, -0.39), (0.094, -0.3)]), with: .color(fox))
        c.fill(M.circle(0.03, -0.26, 0.075), with: .color(fox))
        c.fill(oval(0.072, -0.235, 0.08, 0.055), with: .color(cream))
        c.fill(M.circle(0.106, -0.24, 0.012), with: .color(Palette.face))
        for x: CGFloat in [0.016, 0.062] {
            if asleep {
                c.fill(Path(roundedRect: CGRect(x: x - 0.012, y: -0.274, width: 0.024, height: 0.006), cornerRadius: 0.003),
                       with: .color(Palette.face))
            } else {
                c.fill(M.circle(x, -0.272, 0.01), with: .color(Palette.face))
            }
        }
    }

    private static func drawLighthouse(_ ctx: GraphicsContext, at p: CGPoint, s: CGFloat, lit: Bool) {
        ctx.fill(oval(p.x, p.y + 0.02 * s, 0.5 * s, 0.1 * s), with: .color(Palette.grassDark.opacity(0.7)))
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.scaleBy(x: s, y: s)
        c.fill(oval(0, 0, 0.46, 0.12), with: .color(Color(hex: 0xB8BEC8)))
        c.fill(polygon([(-0.17, 0), (0.17, 0), (0.11, -0.95), (-0.11, -0.95)]), with: .color(Color(hex: 0xF7F3EC)))
        for (from, to) in [(0.2, 0.38), (0.58, 0.76)] {
            let w0 = CGFloat(0.17 - 0.06 * from), w1 = CGFloat(0.17 - 0.06 * to)
            let y0 = CGFloat(-0.95 * from), y1 = CGFloat(-0.95 * to)
            c.fill(polygon([(-w0, y0), (w0, y0), (w1, y1), (-w1, y1)]), with: .color(red))
        }
        c.fill(Path(roundedRect: CGRect(x: -0.04, y: -0.14, width: 0.08, height: 0.14), cornerRadius: 0.035),
               with: .color(Palette.woodDark))
        c.fill(Path(roundedRect: CGRect(x: -0.15, y: -1.0, width: 0.3, height: 0.05), cornerRadius: 0.015),
               with: .color(Color(hex: 0x5A6270)))
        c.fill(Path(CGRect(x: -0.085, y: -1.17, width: 0.17, height: 0.17)), with: .color(lit ? lamp : Color(hex: 0xC9CED6)))
        c.fill(Path(CGRect(x: -0.008, y: -1.17, width: 0.016, height: 0.17)), with: .color(Color(hex: 0x5A6270).opacity(0.6)))
        c.fill(polygon([(-0.12, -1.17), (0.12, -1.17), (0, -1.34)]), with: .color(red))
        c.fill(M.circle(0, -1.35, 0.02), with: .color(Palette.woodDark))
    }

    // MARK: In the air

    /// Butterflies and the bird; both rest at night.
    static func drawAir(_ ctx: GraphicsContext, _ scene: IslandScene, vp: IslandViewport, shape: IslandShape,
                        time: Double, night: Double) {
        guard night < 0.6 else { return }
        let s = vp.scale
        if scene.residents.contains(.butterfly) {
            for i in 0..<2 {
                let k = Double(i)
                let ground = CGPoint(x: shape.rx * (0.35 * sin(time * 0.5 + k * 2.1) + (i == 0 ? -0.3 : 0.25)),
                                     y: shape.ry * 0.3 * cos(time * 0.37 + k))
                let v = vp.view(ground)
                var c = ctx
                c.translateBy(x: v.x, y: v.y - CGFloat(0.55 + 0.15 * sin(time * 1.3 + k)) * s)
                c.rotate(by: .radians(sin(time * 0.9 + k) * 0.3))
                let flap = CGFloat(time == 0 ? 0.8 : 0.25 + 0.75 * abs(sin(time * 10 + k)))
                c.scaleBy(x: s, y: s)
                for side: CGFloat in [-1, 1] {
                    c.fill(oval(side * 0.045 * flap, -0.012, 0.09 * flap, 0.11), with: .color(wingColors[i]))
                    c.fill(oval(side * 0.035 * flap, 0.05, 0.06 * flap, 0.07), with: .color(wingColors[i].opacity(0.75)))
                }
                c.fill(oval(0, 0.012, 0.018, 0.09), with: .color(Palette.face))
            }
        }
        if scene.residents.contains(.bird) {
            let angle = time * 0.45
            let ground = CGPoint(x: shape.rx * 0.75 * cos(angle), y: shape.ry * (-0.2 + 0.5 * sin(angle)))
            let v = vp.view(ground)
            ctx.fill(oval(v.x, v.y, 0.16 * s, 0.04 * s), with: .color(.black.opacity(0.1)))
            var c = ctx
            c.translateBy(x: v.x, y: v.y - CGFloat(1.5 + 0.1 * sin(time * 2)) * s)
            c.scaleBy(x: (sin(angle) > 0 ? -1 : 1) * s, y: s)
            let flap = CGFloat(time == 0 ? 0.6 : sin(time * 9))
            c.fill(polygon([(-0.09, -0.01), (-0.17, -0.05), (-0.16, 0.03)]), with: .color(birdDark))
            c.fill(oval(0, 0, 0.2, 0.12), with: .color(birdBlue))
            c.fill(oval(0.01, 0.025, 0.13, 0.06), with: .color(Color(hex: 0xEAF4FD)))
            c.fill(M.circle(0.09, -0.04, 0.055), with: .color(birdBlue))
            c.fill(polygon([(0.14, -0.045), (0.185, -0.03), (0.14, -0.015)]), with: .color(beak))
            c.fill(M.circle(0.105, -0.05, 0.01), with: .color(Palette.face))
            c.fill(polygon([(-0.05, -0.02), (0.04, -0.02), (-0.02, -0.02 - 0.14 * flap)]), with: .color(birdDark))
        }
    }

    /// Light sources, drawn over the night tint so they glow: the lighthouse beam and fireflies.
    static func drawLights(_ ctx: GraphicsContext, _ scene: IslandScene, vp: IslandViewport, shape: IslandShape,
                           time: Double, night: Double) {
        let s = vp.scale
        if scene.lighthouse == .lit {
            let base = vp.view(lighthouseSpot(shape))
            let source = CGPoint(x: base.x, y: base.y - 1.085 * s)
            let turn = cos(time * 0.7)
            let reach = 3.2 * s * CGFloat(turn)
            let spread = (0.06 + 0.2 * CGFloat(abs(turn))) * 3.2 * s
            let tip = CGPoint(x: source.x + reach, y: source.y - 0.25 * s)
            var beam = Path()
            beam.move(to: source)
            beam.addLine(to: CGPoint(x: tip.x, y: tip.y - spread))
            beam.addLine(to: CGPoint(x: tip.x, y: tip.y + spread))
            beam.closeSubpath()
            let strength = (0.22 + 0.3 * night) * (0.35 + 0.65 * abs(turn))
            ctx.fill(beam, with: .linearGradient(Gradient(colors: [lamp.opacity(strength), lamp.opacity(0)]),
                                                 startPoint: source, endPoint: tip))
            ctx.fill(M.circle(source.x, source.y, 0.45 * s), with: .radialGradient(
                Gradient(colors: [lamp.opacity(0.55), lamp.opacity(0)]), center: source, startRadius: 0, endRadius: 0.45 * s))
        }
        if scene.residents.contains(.fireflies), night > 0.3 {
            for i in 0..<9 {
                let k = Double(i)
                let ground = CGPoint(x: shape.rx * 0.85 * sin(time * 0.13 * (1 + M.rnd(31, i)) + k * 1.7),
                                     y: shape.ry * 0.8 * cos(time * 0.11 * (1 + M.rnd(32, i)) + k * 2.3))
                let v = vp.view(ground)
                let at = CGPoint(x: v.x, y: v.y - CGFloat(0.25 + 0.7 * M.rnd(33, i) + 0.1 * sin(time * 0.9 + k)) * s)
                var c = ctx
                c.opacity = night * (0.25 + 0.75 * pow(sin(time * 1.4 + k * 2.1), 2))
                c.fill(M.circle(at.x, at.y, 0.16 * s), with: .radialGradient(
                    Gradient(colors: [glow.opacity(0.55), glow.opacity(0)]), center: at, startRadius: 0, endRadius: 0.16 * s))
                c.fill(M.circle(at.x, at.y, 0.022 * s), with: .color(glow))
            }
        }
    }
}

extension LivingPainter {
    /// A tilted watering can with falling drops, shown over the plant during the break after a session.
    static func drawWateringCan(_ ctx: GraphicsContext, at p: CGPoint, unit u: CGFloat, time: Double) {
        let tilt = -0.45 + sin(time * 1.5) * 0.06
        let dark = Color(hex: 0x6FB3DD)
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(tilt))
        c.scaleBy(x: u, y: u)
        c.stroke(Path(ellipseIn: CGRect(x: 0.02, y: -0.07, width: 0.1, height: 0.1)), with: .color(dark), lineWidth: 0.018)
        c.fill(polygon([(-0.06, -0.01), (-0.17, -0.075), (-0.155, -0.095), (-0.06, -0.045)]), with: .color(dark))
        c.fill(Path(roundedRect: CGRect(x: -0.07, y: -0.065, width: 0.14, height: 0.11), cornerRadius: 0.025),
               with: .color(Palette.river))
        c.fill(Path(roundedRect: CGRect(x: -0.055, y: -0.055, width: 0.03, height: 0.07), cornerRadius: 0.012),
               with: .color(.white.opacity(0.35)))
        // The spout's tip in unrotated coordinates, where the drops start.
        let tip = CGPoint(x: p.x + u * CGFloat(-0.165 * cos(tilt) + 0.085 * sin(tilt)),
                          y: p.y + u * CGFloat(-0.165 * sin(tilt) - 0.085 * cos(tilt)))
        for i in 0..<4 {
            let phase = (time * 1.2 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
            var drop = ctx
            drop.opacity = 1 - phase
            drop.fill(M.circle(tip.x - u * 0.008 * CGFloat(i), tip.y + u * 0.3 * CGFloat(phase), u * 0.012),
                      with: .color(Palette.river))
        }
    }
}

extension Garden {
    /// What surrounds the plants of an island right now. Lighthouse and seedbed belong to the island being planted.
    func scene(for island: Int, timer: FocusTimer?, date: Date? = Date()) -> IslandScene {
        var scene = IslandScene()
        if livingSky {
            scene.hour = date.map(Daylight.hour(of:))
            scene.month = Self.currentMonth
        }
        scene.residents = Set(residents)
        if island == currentIsland {
            scene.lighthouse = weeklyGoal == 0 ? .none : weeklyGoalReached ? .lit : .dark
            scene.saplings = saplings.filter { !(timer?.isActive == true && $0.id == timer?.saplingID) }
        }
        return scene
    }
}

/// Small picture of an island resident for lists.
struct ResidentIcon: View {
    let resident: Resident

    var body: some View {
        Canvas { ctx, size in
            let shape = IslandShape(plantCount: 1)
            var scene = IslandScene()
            scene.residents = [resident]
            // A viewport centred on where the animal appears, so the same drawing code serves as its icon.
            let focus: (center: CGPoint, lift: Double, zoom: Double)
            switch resident {
            case .butterfly: focus = (CGPoint(x: shape.rx * -0.3, y: shape.ry * 0.3), 0.55, 4.2)
            case .bird: focus = (CGPoint(x: shape.rx * 0.75, y: shape.ry * -0.2), 1.5, 3.4)
            case .bunny: focus = (CGPoint(x: shape.rx * -0.70, y: shape.ry * 0.50), 0.15, 2.6)
            case .fox: focus = (CGPoint(x: shape.rx * 0.56, y: shape.ry * 0.70), 0.2, 2.2)
            case .fireflies: focus = (CGPoint(x: 0, y: 0), 0.5, 1.2)
            }
            let scale = size.height * focus.zoom / 2
            let vp = IslandViewport(scale: scale, origin: CGPoint(
                x: size.width / 2 - focus.center.x * scale,
                y: size.height / 2 - (focus.center.y - focus.lift) * scale))
            for item in LivingPainter.groundItems(scene, vp: vp, shape: shape, time: 0, night: 0) { item.draw(ctx) }
            LivingPainter.drawAir(ctx, scene, vp: vp, shape: shape, time: 0, night: 0)
            LivingPainter.drawLights(ctx, scene, vp: vp, shape: shape, time: 0.6, night: 1)
        }
    }
}
