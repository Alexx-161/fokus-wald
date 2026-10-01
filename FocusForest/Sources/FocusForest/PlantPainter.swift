import SwiftUI

enum TreeMath {
    static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }

    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamp((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    /// Deterministic pseudo-random value in 0..<1 for a given seed and slot.
    static func rnd(_ seed: Double, _ k: Int) -> Double {
        let v = sin(seed * 9301.0 + Double(k) * 49.297 + 0.5) * 43758.5453
        return v - floor(v)
    }

    static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    static func quad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(x: mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x,
                       y: mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y)
    }
}

/// Draws any plant at a growth `progress` (0 = seedling, 1 = fully grown).
/// `base` is where the plant meets the ground; `unit` scales it (a grown tree is ≈ 0.6·unit tall).
enum PlantPainter {
    private typealias M = TreeMath

    private static let blobs: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0, 0.12, 0.95), (-0.62, 0.30, 0.62), (0.62, 0.30, 0.62),
        (-0.36, -0.42, 0.64), (0.37, -0.40, 0.60), (0, -0.62, 0.55),
    ]
    private static let baubles: [Color] = [0xE8645A, 0xFFD66B, 0x8CCBEF].map { Color(hex: $0) }
    private static let rainbow: [Color] = [0xF7A8B8, 0xFFC98B, 0xFFE89A, 0xA8E6A1, 0xA8D2F5, 0xC9B6F2].map { Color(hex: $0) }

    static func draw(
        _ context: GraphicsContext,
        species s: PlantSpecies,
        base: CGPoint,
        unit u: CGFloat,
        progress p: Double,
        seed: Double,
        time: Double,
        ground: Bool = true,
        detail: Bool = true,
        golden: Bool = false
    ) {
        let g = CGFloat(M.smooth(0, 1, p))
        var ctx = context
        ctx.translateBy(x: base.x, y: base.y)

        if ground {
            let w = u * (0.34 + 0.14 * g), h = u * 0.075
            ctx.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(Palette.soil))
            ctx.fill(Path(ellipseIn: CGRect(x: -w / 2 + u * 0.03, y: -h / 2, width: w - u * 0.06, height: h * 0.5)),
                     with: .color(Palette.soilLight))
        }
        if time != 0 {
            ctx.rotate(by: .radians(sin(time * 1.3 + seed * 40) * 0.03 * Double(g)))
        }

        let face: (center: CGPoint, radius: CGFloat)?
        switch s.kind {
        case .roundTree, .pine, .festive, .rainbow, .crystal:
            face = drawTree(ctx, s, u: u, g: g, p: p, seed: seed, time: time, detail: detail)
        case .tulip, .sunflower, .daisy, .bell:
            face = drawFlower(ctx, s, u: u, g: g, p: p, seed: seed)
        case .toadstool, .porcini, .glowshroom:
            face = drawMushroom(ctx, s, u: u, g: g, p: p, time: time, detail: detail)
        }
        if detail, let face {
            drawFace(ctx, center: face.center, radius: face.radius, p: p, seed: seed, time: time)
        }
        if golden, let face {
            drawGolden(ctx, center: face.center, radius: face.radius, p: p, seed: seed, time: time)
        }
    }

    /// The rare variant grown by long sessions: a warm glow and twinkling golden stars around the crown.
    private static func drawGolden(_ ctx: GraphicsContext, center c: CGPoint, radius R: CGFloat,
                                   p: Double, seed: Double, time: Double) {
        let a = M.smooth(0.8, 1.0, p)
        guard a > 0.01 else { return }
        let glowR = R * 2.1
        ctx.fill(M.circle(c.x, c.y, glowR), with: .radialGradient(
            Gradient(colors: [Palette.star.opacity(0.3 * a), Palette.star.opacity(0)]),
            center: c, startRadius: 0, endRadius: glowR))
        for i in 0..<5 {
            let ang = Double(i) * 2 * .pi / 5 + seed * 6 - .pi / 2
            let rr = R * CGFloat(1.15 + 0.3 * M.rnd(seed, 70 + i))
            let twinkle = time == 0 ? 1 : 0.45 + 0.55 * (0.5 + 0.5 * sin(time * 2.2 + Double(i) * 1.9))
            var sc = ctx
            sc.opacity = a * twinkle
            let at = CGPoint(x: c.x + CGFloat(cos(ang)) * rr, y: c.y + CGFloat(sin(ang)) * rr * 0.85)
            sc.fill(star(at: at, radius: R * 0.16), with: .color(Palette.star))
            sc.fill(M.circle(at.x, at.y, R * 0.04), with: .color(.white))
        }
    }

    // MARK: Trees

    private static func drawTree(_ ctx: GraphicsContext, _ s: PlantSpecies, u: CGFloat, g: CGFloat, p: Double,
                                 seed: Double, time: Double, detail: Bool) -> (CGPoint, CGFloat)? {
        let trunkH = u * (0.05 + 0.22 * g)
        let trunkW = u * (0.024 + 0.04 * g)
        let trunkColor = s.kind == .crystal ? Palette.crystalTrunk : Palette.trunk
        ctx.fill(Path(roundedRect: CGRect(x: -trunkW / 2, y: -trunkH, width: trunkW, height: trunkH + u * 0.012),
                      cornerRadius: trunkW / 2), with: .color(trunkColor))
        if detail {
            ctx.fill(Path(roundedRect: CGRect(x: -trunkW * 0.28, y: -trunkH * 0.9, width: trunkW * 0.2, height: trunkH * 0.75),
                          cornerRadius: trunkW * 0.1), with: .color(.white.opacity(0.18)))
        }
        drawSprout(ctx, top: CGPoint(x: 0, y: -trunkH + u * 0.005), u: u, p: p)

        guard M.smooth(0.18, 1, p) > 0.001 else { return nil }
        let crown: (CGPoint, CGFloat)
        switch s.kind {
        case .pine, .festive: crown = drawPine(ctx, s, u: u, trunkH: trunkH, p: p)
        case .crystal: crown = drawCrystal(ctx, s, u: u, trunkH: trunkH, p: p, seed: seed, time: time)
        case .rainbow:
            crown = drawRound(ctx, u: u, trunkH: trunkH, p: p, seed: seed) { i in
                let c = rainbow[i % rainbow.count]
                return (c, c, Color.white.opacity(0.45))
            }
        default:
            crown = drawRound(ctx, u: u, trunkH: trunkH, p: p, seed: seed) { _ in (s.main, s.shade, s.light) }
        }
        if detail && s.kind != .crystal {
            drawBlossoms(ctx, color: s.accent, crown: crown, p: p, seed: seed)
        }
        return crown
    }

    private static func drawSprout(_ ctx: GraphicsContext, top: CGPoint, u: CGFloat, p: Double) {
        let alpha = 1 - M.smooth(0.2, 0.38, p)
        guard alpha > 0.01 else { return }
        let ls = u * CGFloat(0.06 + 0.06 * M.smooth(0, 0.2, p))
        for dir in [-1.0, 1.0] {
            var leaf = ctx
            leaf.opacity = alpha
            leaf.translateBy(x: top.x, y: top.y)
            leaf.rotate(by: .radians(-dir * 0.55))
            leaf.fill(Path(ellipseIn: CGRect(x: dir > 0 ? 0 : -ls, y: -ls * 0.27, width: ls, height: ls * 0.54)),
                      with: .color(Palette.sprout))
        }
    }

    private static func drawRound(_ ctx: GraphicsContext, u: CGFloat, trunkH: CGFloat, p: Double, seed: Double,
                                  colors: (Int) -> (main: Color, shade: Color, light: Color)) -> (CGPoint, CGFloat) {
        let R = u * 0.2
        let center = CGPoint(x: 0, y: -trunkH - R * 0.35)
        var circles: [(index: Int, point: CGPoint, r: CGFloat)] = []
        for (i, b) in blobs.enumerated() {
            let a = CGFloat(M.smooth(0.18 + Double(i) * 0.07, 0.55 + Double(i) * 0.07, p))
            guard a > 0.001 else { continue }
            let jx = CGFloat(M.rnd(seed, i) - 0.5) * 0.14
            let jy = CGFloat(M.rnd(seed, i + 10) - 0.5) * 0.10
            let spread = R * (0.35 + 0.65 * a)
            circles.append((i, CGPoint(x: center.x + (b.x + jx) * spread, y: center.y + (b.y + jy) * spread), R * b.r * a))
        }
        for c in circles {
            let shadow = M.circle(c.point.x, c.point.y + R * 0.09, c.r)
            ctx.fill(shadow, with: .color(colors(c.index).shade))
            ctx.fill(shadow, with: .color(.black.opacity(0.08)))
        }
        for c in circles {
            ctx.fill(M.circle(c.point.x, c.point.y, c.r), with: .color(colors(c.index).main))
        }
        for c in circles where [0, 3, 4, 5].contains(c.index) {
            ctx.fill(M.circle(c.point.x - c.r * 0.32, c.point.y - c.r * 0.34, c.r * 0.3), with: .color(colors(c.index).light))
        }
        return (CGPoint(x: center.x, y: center.y + R * 0.18), R)
    }

    private static func drawPine(_ ctx: GraphicsContext, _ s: PlantSpecies, u: CGFloat, trunkH: CGFloat,
                                 p: Double) -> (CGPoint, CGFloat) {
        var faceCenter = CGPoint(x: 0, y: -trunkH)
        var apex = CGPoint(x: 0, y: -trunkH)
        let corner = StrokeStyle(lineWidth: u * 0.035, lineJoin: .round)
        for k in 0..<3 {
            let a = CGFloat(M.smooth(0.18 + Double(k) * 0.14, 0.58 + Double(k) * 0.14, p))
            guard a > 0.001 else { continue }
            let w = u * (0.44 - CGFloat(k) * 0.1) * a
            let h = u * (0.2 - CGFloat(k) * 0.025) * a
            let baseY = -trunkH * 0.55 - CGFloat(k) * u * 0.11
            var tri = Path()
            tri.move(to: CGPoint(x: 0, y: baseY - h))
            tri.addLine(to: CGPoint(x: w / 2, y: baseY))
            tri.addLine(to: CGPoint(x: -w / 2, y: baseY))
            tri.closeSubpath()
            let shadeTri = tri.offsetBy(dx: 0, dy: u * 0.018)
            ctx.fill(shadeTri, with: .color(s.shade))
            ctx.stroke(shadeTri, with: .color(s.shade), style: corner)
            ctx.fill(tri, with: .color(s.main))
            ctx.stroke(tri, with: .color(s.main), style: corner)
            ctx.fill(M.circle(-w * 0.14, baseY - h * 0.55, u * 0.016 * a), with: .color(s.light))
            if s.kind == .festive {
                for (j, dx) in [-0.24, 0.05, 0.27].enumerated() where k < 2 || j != 1 {
                    ctx.fill(M.circle(w * CGFloat(dx), baseY - h * CGFloat(0.12 + 0.12 * Double(j % 2)), u * 0.022 * a),
                             with: .color(baubles[(j + k) % baubles.count]))
                }
            }
            if k == 0 { faceCenter = CGPoint(x: 0, y: baseY - h * 0.3) }
            apex = CGPoint(x: 0, y: baseY - h)
        }
        let starA = M.smooth(0.9, 1.0, p)
        if starA > 0.01 {
            var c = ctx
            c.opacity = starA
            c.fill(star(at: CGPoint(x: apex.x, y: apex.y - u * 0.01), radius: u * 0.045), with: .color(Palette.star))
        }
        return (faceCenter, u * 0.16)
    }

    private static func drawCrystal(_ ctx: GraphicsContext, _ s: PlantSpecies, u: CGFloat, trunkH: CGFloat,
                                    p: Double, seed: Double, time: Double) -> (CGPoint, CGFloat) {
        let R = u * 0.2
        let c = CGPoint(x: 0, y: -trunkH - R * 0.25)
        let shards: [(deg: Double, len: CGFloat, wid: CGFloat)] = [
            (-90, 1.75, 0.5), (-130, 1.4, 0.42), (-50, 1.4, 0.42), (-165, 0.95, 0.34), (-15, 0.95, 0.34),
        ]
        for i in [3, 4, 1, 2, 0] {
            let a = CGFloat(M.smooth(0.2 + Double(i) * 0.08, 0.6 + Double(i) * 0.08, p))
            guard a > 0.001 else { continue }
            let sh = shards[i]
            let ang = sh.deg * .pi / 180
            let d = CGPoint(x: cos(ang), y: sin(ang))
            let n = CGPoint(x: -d.y, y: d.x)
            let L = R * sh.len * a, w = R * sh.wid * a
            func pt(_ along: CGFloat, _ side: CGFloat) -> CGPoint {
                CGPoint(x: c.x + d.x * along + n.x * side, y: c.y + d.y * along + n.y * side)
            }
            var shard = Path()
            shard.move(to: pt(0, w / 2))
            shard.addLine(to: pt(L * 0.78, w / 2))
            shard.addLine(to: pt(L, 0))
            shard.addLine(to: pt(L * 0.78, -w / 2))
            shard.addLine(to: pt(0, -w / 2))
            shard.closeSubpath()
            ctx.fill(shard, with: .color(i.isMultiple(of: 2) ? s.main : s.shade))
            var facet = Path()
            facet.move(to: pt(0, 0))
            facet.addLine(to: pt(L * 0.78, w / 2))
            facet.addLine(to: pt(L, 0))
            facet.closeSubpath()
            ctx.fill(facet, with: .color(s.light.opacity(0.75)))
        }
        let orbA = CGFloat(M.smooth(0.3, 0.7, p))
        if orbA > 0.01 {
            let r = R * 0.62 * orbA
            ctx.fill(M.circle(c.x, c.y, r), with: .radialGradient(
                Gradient(colors: [s.light, s.main, s.accent]),
                center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
        }
        let sparkle = M.smooth(0.8, 1.0, p)
        if sparkle > 0.01 {
            for i in 0..<5 {
                let ang = Double.pi * (1.0 + M.rnd(seed, 50 + i))
                let rr = R * CGFloat(0.9 + 0.5 * M.rnd(seed, 60 + i))
                let twinkle = time == 0 ? 1 : 0.5 + 0.5 * sin(time * 2.5 + Double(i) * 1.7)
                var sc = ctx
                sc.opacity = sparkle * twinkle
                sc.fill(star(at: CGPoint(x: c.x + CGFloat(cos(ang)) * rr, y: c.y + CGFloat(sin(ang)) * rr),
                             radius: R * 0.09), with: .color(.white))
            }
        }
        return (CGPoint(x: c.x, y: c.y + R * 0.04), R * 1.0)
    }

    private static func drawBlossoms(_ ctx: GraphicsContext, color: Color, crown: (center: CGPoint, radius: CGFloat),
                                     p: Double, seed: Double) {
        let a = M.smooth(0.78, 1.0, p)
        guard a > 0.01 else { return }
        let R = crown.radius
        for i in 0..<7 {
            let ang = Double.pi * (0.95 + 1.1 * M.rnd(seed, 30 + i))
            let rr = R * CGFloat(0.55 + 0.4 * M.rnd(seed, 40 + i))
            let x = crown.center.x + CGFloat(cos(ang)) * rr
            let y = crown.center.y - R * 0.25 + CGFloat(sin(ang)) * rr
            ctx.fill(M.circle(x, y, R * 0.075 * CGFloat(a)), with: .color(color))
        }
    }

    // MARK: Flowers

    private static func drawFlower(_ ctx: GraphicsContext, _ s: PlantSpecies, u: CGFloat, g: CGFloat, p: Double,
                                   seed: Double) -> (CGPoint, CGFloat)? {
        let stemH = u * (0.05 + 0.33 * g)
        let bend = u * 0.04 * CGFloat(M.rnd(seed, 1) - 0.5)
        let tip: CGPoint
        let control: CGPoint
        if s.kind == .bell {
            tip = CGPoint(x: u * 0.11 * g, y: -stemH * 0.85)
            control = CGPoint(x: -u * 0.02, y: -stemH * 1.2)
        } else {
            tip = CGPoint(x: bend, y: -stemH)
            control = CGPoint(x: -bend, y: -stemH * 0.5)
        }
        var stem = Path()
        stem.move(to: .zero)
        stem.addQuadCurve(to: tip, control: control)
        ctx.stroke(stem, with: .color(Palette.stem), style: StrokeStyle(lineWidth: max(1, u * 0.022), lineCap: .round))

        let leafA = CGFloat(M.smooth(0.12, 0.45, p))
        if leafA > 0.01 {
            for (t, dir) in [(CGFloat(0.3), -1.0), (CGFloat(0.5), 1.0)] {
                let at = M.quad(.zero, control, tip, t)
                let ls = u * 0.1 * leafA
                var leaf = ctx
                leaf.translateBy(x: at.x, y: at.y)
                leaf.rotate(by: .radians(-dir * 0.5))
                leaf.fill(Path(ellipseIn: CGRect(x: dir > 0 ? 0 : -ls, y: -ls * 0.22, width: ls, height: ls * 0.44)),
                          with: .color(Palette.leaf))
            }
        }
        drawSprout(ctx, top: tip, u: u, p: p)

        let bud = CGFloat(M.smooth(0.28, 0.55, p))
        let open = CGFloat(M.smooth(0.55, 0.95, p))
        guard bud > 0.01 else { return nil }

        switch s.kind {
        case .tulip:
            let h = u * 0.19 * (0.45 + 0.55 * bud)
            let w = h * 0.62
            let c = CGPoint(x: tip.x, y: tip.y - h * 0.4)
            for dir in [-1.0, 1.0] {
                var petal = ctx
                petal.translateBy(x: c.x, y: c.y + h * 0.15)
                petal.rotate(by: .radians(dir * (0.18 + 0.32 * Double(open))))
                petal.fill(Path(ellipseIn: CGRect(x: -w / 2 + CGFloat(dir) * w * 0.25, y: -h * 0.6, width: w, height: h)),
                           with: .color(s.shade))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.55, y: c.y - h * 0.5, width: w * 1.1, height: h)), with: .color(s.main))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.35, y: c.y - h * 0.38, width: w * 0.28, height: h * 0.3)),
                     with: .color(s.light))
            return (CGPoint(x: c.x, y: c.y + h * 0.05), w * 0.95)

        case .sunflower, .daisy:
            let sun = s.kind == .sunflower
            let diskR = u * (sun ? 0.09 : 0.065) * (0.5 + 0.5 * bud)
            let petalL = u * (sun ? 0.11 : 0.105) * open
            let petalW = u * (sun ? 0.055 : 0.04)
            let count = sun ? 14 : 12
            if open > 0.01 {
                for i in 0..<count {
                    var petal = ctx
                    petal.translateBy(x: tip.x, y: tip.y)
                    petal.rotate(by: .radians(Double(i) * 2 * .pi / Double(count) + seed))
                    let rect = CGRect(x: diskR * 0.6, y: -petalW / 2, width: petalL + diskR * 0.4, height: petalW)
                    if !sun {
                        petal.fill(Path(ellipseIn: rect.insetBy(dx: -u * 0.005, dy: -u * 0.005)), with: .color(s.shade))
                    }
                    petal.fill(Path(ellipseIn: rect), with: .color(sun && i.isMultiple(of: 2) ? s.shade : s.main))
                }
            }
            if open < 0.99 {
                var budCtx = ctx
                budCtx.opacity = Double(1 - open)
                budCtx.fill(M.circle(tip.x, tip.y, diskR * 1.3), with: .color(Palette.leaf))
            }
            ctx.fill(M.circle(tip.x, tip.y, diskR), with: .color(s.accent))
            if sun {
                for i in 0..<6 {
                    let ang = Double(i) * .pi / 3 + 0.3
                    ctx.fill(M.circle(tip.x + CGFloat(cos(ang)) * diskR * 0.7, tip.y + CGFloat(sin(ang)) * diskR * 0.7, diskR * 0.08),
                             with: .color(.black.opacity(0.15)))
                }
            }
            return (CGPoint(x: tip.x, y: tip.y + diskR * 0.05), diskR * 1.55)

        default:
            let bh = u * 0.19 * (0.45 + 0.55 * bud)
            let top = tip
            let flare = 0.8 + 0.2 * open
            let bw = bh * 0.95
            let bottomY = top.y + bh * 0.9
            var bell = Path()
            bell.move(to: CGPoint(x: top.x + bw * 0.3, y: top.y))
            bell.addQuadCurve(to: CGPoint(x: top.x - bw * 0.3, y: top.y), control: CGPoint(x: top.x, y: top.y - bh * 0.18))
            bell.addQuadCurve(to: CGPoint(x: top.x - bw * 0.5 * flare, y: bottomY), control: CGPoint(x: top.x - bw * 0.5, y: top.y + bh * 0.25))
            let xs: [CGFloat] = [-0.5, -0.17, 0.17, 0.5]
            for i in 0..<3 {
                let x0 = xs[i] * flare, x1 = xs[i + 1] * flare
                bell.addQuadCurve(to: CGPoint(x: top.x + bw * x1, y: bottomY),
                                  control: CGPoint(x: top.x + bw * (x0 + x1) / 2, y: bottomY + bh * 0.16))
            }
            bell.addQuadCurve(to: CGPoint(x: top.x + bw * 0.3, y: top.y), control: CGPoint(x: top.x + bw * 0.5, y: top.y + bh * 0.25))
            bell.closeSubpath()
            ctx.fill(bell, with: .color(s.main))
            ctx.fill(Path(ellipseIn: CGRect(x: top.x - bw * 0.36, y: top.y + bh * 0.12, width: bw * 0.18, height: bh * 0.38)),
                     with: .color(s.light))
            return (CGPoint(x: top.x, y: top.y + bh * 0.5), bw * 0.85)
        }
    }

    // MARK: Mushrooms

    private static func drawMushroom(_ ctx: GraphicsContext, _ s: PlantSpecies, u: CGFloat, g: CGFloat, p: Double,
                                     time: Double, detail: Bool) -> (CGPoint, CGFloat) {
        let chunky: CGFloat = s.kind == .porcini ? 1.35 : 1
        let stemH = u * (0.03 + 0.17 * g)
        let stemW = u * (0.05 + 0.07 * g) * chunky
        let capR = u * (0.07 + 0.16 * g) * (s.kind == .porcini ? 1.05 : 1)
        let capBottom = -stemH

        if s.kind == .glowshroom {
            let glowR = capR * 2.4
            ctx.fill(M.circle(0, capBottom - capR * 0.3, glowR), with: .radialGradient(
                Gradient(colors: [s.accent.opacity(0.55), s.accent.opacity(0)]),
                center: CGPoint(x: 0, y: capBottom - capR * 0.3), startRadius: 0, endRadius: glowR))
        }

        ctx.fill(Path(roundedRect: CGRect(x: -stemW / 2, y: capBottom - capR * 0.2, width: stemW, height: stemH + capR * 0.2 + u * 0.01),
                      cornerRadius: stemW * 0.45), with: .color(s.kind == .porcini ? s.accent : Palette.mushroomStem))
        ctx.fill(Path(ellipseIn: CGRect(x: -capR * 0.92, y: capBottom - capR * 0.16, width: capR * 1.84, height: capR * 0.34)),
                 with: .color(Palette.gills))

        var dome = Path()
        dome.move(to: CGPoint(x: -capR, y: capBottom))
        dome.addCurve(to: CGPoint(x: capR, y: capBottom),
                      control1: CGPoint(x: -capR * 1.02, y: capBottom - capR * 1.35),
                      control2: CGPoint(x: capR * 1.02, y: capBottom - capR * 1.35))
        dome.addQuadCurve(to: CGPoint(x: -capR, y: capBottom), control: CGPoint(x: 0, y: capBottom + capR * 0.22))
        dome.closeSubpath()
        ctx.fill(dome, with: .linearGradient(Gradient(colors: [s.light, s.main, s.shade]),
                                             startPoint: CGPoint(x: 0, y: capBottom - capR),
                                             endPoint: CGPoint(x: 0, y: capBottom + capR * 0.15)))
        ctx.fill(Path(ellipseIn: CGRect(x: -capR * 0.62, y: capBottom - capR * 0.82, width: capR * 0.36, height: capR * 0.2)),
                 with: .color(.white.opacity(0.45)))

        if s.kind == .toadstool {
            let dots: [(CGFloat, CGFloat, CGFloat)] = [
                (-0.62, -0.42, 0.11), (-0.3, -0.85, 0.12), (0.2, -0.93, 0.1), (0.6, -0.6, 0.12), (0.75, -0.25, 0.07), (-0.82, -0.15, 0.06),
            ]
            for d in dots {
                ctx.fill(M.circle(d.0 * capR, capBottom + d.1 * capR, d.2 * capR), with: .color(s.accent))
            }
        }
        if s.kind == .glowshroom && detail {
            for i in 0..<4 {
                let twinkle = time == 0 ? 1 : 0.5 + 0.5 * sin(time * 2 + Double(i) * 1.9)
                var sc = ctx
                sc.opacity = twinkle * M.smooth(0.6, 1, p)
                let x = capR * CGFloat([-1.5, 1.4, -0.9, 1.0][i])
                let y = capBottom - capR * CGFloat([0.9, 1.2, 1.7, 0.2][i])
                sc.fill(star(at: CGPoint(x: x, y: y), radius: capR * 0.13), with: .color(s.accent))
            }
        }
        return (CGPoint(x: 0, y: capBottom - capR * 0.36), capR * 0.85)
    }

    // MARK: Shared details

    private static func drawFace(_ ctx: GraphicsContext, center c: CGPoint, radius R: CGFloat,
                                 p: Double, seed: Double, time: Double) {
        let a = M.smooth(0.45, 0.7, p)
        guard a > 0.01 else { return }
        var f = ctx
        f.opacity = a
        let er = R * 0.075
        let blinking = time != 0 && (time + seed * 11).truncatingRemainder(dividingBy: 4.5) < 0.13
        for d: CGFloat in [-1, 1] {
            let x = c.x + d * R * 0.3, y = c.y
            if blinking {
                f.fill(Path(roundedRect: CGRect(x: x - er, y: y - er * 0.2, width: er * 2, height: er * 0.4), cornerRadius: er * 0.2),
                       with: .color(Palette.face))
            } else {
                f.fill(M.circle(x, y, er), with: .color(Palette.face))
                f.fill(M.circle(x - er * 0.3, y - er * 0.35, er * 0.35), with: .color(.white))
            }
            f.fill(Path(ellipseIn: CGRect(x: x + d * R * 0.12 - R * 0.11, y: y + R * 0.1, width: R * 0.22, height: R * 0.12)),
                   with: .color(Palette.blush.opacity(0.75)))
        }
        var mouth = Path()
        mouth.move(to: CGPoint(x: c.x - R * 0.07, y: c.y + R * 0.08))
        mouth.addQuadCurve(to: CGPoint(x: c.x + R * 0.07, y: c.y + R * 0.08), control: CGPoint(x: c.x, y: c.y + R * 0.19))
        f.stroke(mouth, with: .color(Palette.face), style: StrokeStyle(lineWidth: max(0.8, R * 0.035), lineCap: .round))
    }

    static func star(at c: CGPoint, radius r: CGFloat) -> Path {
        var path = Path()
        for i in 0..<10 {
            let rr = i.isMultiple(of: 2) ? r : r * 0.45
            let ang = -Double.pi / 2 + Double(i) * Double.pi / 5
            let pt = CGPoint(x: c.x + CGFloat(cos(ang)) * rr, y: c.y + CGFloat(sin(ang)) * rr)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        path.closeSubpath()
        return path
    }
}

/// Static preview of a species, fully grown unless told otherwise (catalog cards, pickers, saplings).
struct PlantIcon: View {
    let species: PlantSpecies
    var seed: Double = 0.37
    var progress: Double = 1
    var golden = false

    var body: some View {
        Canvas { ctx, size in
            let u = min(size.width, size.height / 0.7)
            PlantPainter.draw(ctx, species: species, base: CGPoint(x: size.width / 2, y: size.height * 0.93),
                              unit: u, progress: progress, seed: seed, time: 0, ground: false, detail: u > 40,
                              golden: golden)
        }
    }
}
