import SwiftUI

enum PlantCategory: String, CaseIterable, Identifiable {
    case tree, flower, mushroom, special, seasonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tree: return "Bäume"
        case .flower: return "Blumen"
        case .mushroom: return "Pilze"
        case .special: return "Besondere"
        case .seasonal: return "Saison"
        }
    }

    var symbol: String {
        switch self {
        case .tree: return "tree.fill"
        case .flower: return "camera.macro"
        case .mushroom: return "umbrella.fill"
        case .special: return "sparkles"
        case .seasonal: return "calendar"
        }
    }
}

struct PlantSpecies: Identifiable {
    /// `festive` is a pine decorated with baubles.
    enum Kind { case roundTree, pine, festive, rainbow, crystal, tulip, sunflower, daisy, bell, toadstool, porcini, glowshroom }

    let id: String
    let name: String
    let category: PlantCategory
    let kind: Kind
    let main: Color
    let shade: Color
    let light: Color
    /// Strong tone used for buttons and the progress ring.
    let deep: Color
    /// Blossoms, dots, flower centers or glow, depending on the kind.
    let accent: Color
    /// Number of completed sessions needed before this plant can be chosen.
    let unlockAt: Int
    /// Seasonal plants can only be planted during this month (1–12); nil for everything else.
    let month: Int?
    let blurb: String

    private init(_ id: String, _ name: String, _ category: PlantCategory, _ kind: Kind,
                 _ colors: [UInt32], unlockAt: Int = 0, month: Int? = nil, _ blurb: String) {
        self.id = id
        self.name = name
        self.category = category
        self.kind = kind
        main = Color(hex: colors[0])
        shade = Color(hex: colors[1])
        light = Color(hex: colors[2])
        deep = Color(hex: colors[3])
        accent = Color(hex: colors[4])
        self.unlockAt = unlockAt
        self.month = month
        self.blurb = blurb
    }

    /// Relative size on the island, so flowers and mushrooms stay smaller than trees.
    var islandScale: Double {
        if category == .special { return 1.08 }
        switch kind {
        case .roundTree, .pine, .festive, .rainbow, .crystal: return 1.0
        case .tulip, .sunflower, .daisy, .bell: return 0.72
        case .toadstool, .porcini, .glowshroom: return 0.64
        }
    }

    static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September",
                             "Oktober", "November", "Dezember"]
    var monthName: String? { month.map { Self.monthNames[$0 - 1] } }

    /// Sessions of this length or more grow the rare golden variant.
    static let goldenMinutes = 50
    static func isGolden(minutes: Int) -> Bool { minutes >= goldenMinutes }

    static let all: [PlantSpecies] = [
        PlantSpecies("minze", "Minzbäumchen", .tree, .roundTree, [0x8FD694, 0x6BBF7A, 0xBDEBC1, 0x5BAE6C, 0xF07C7C],
                     unlockAt: 0, "Frisch und rund – trägt kleine rote Äpfel."),
        PlantSpecies("kirsche", "Kirschblüte", .tree, .roundTree, [0xF7B6C8, 0xEC94AE, 0xFDDAE4, 0xE07A99, 0xFFFFFF],
                     unlockAt: 0, "Zartrosa Wolken voller Blüten."),
        PlantSpecies("tanne", "Tännchen", .tree, .pine, [0x6CC093, 0x4FA478, 0x9BDDB8, 0x3F9468, 0xFFD66B],
                     unlockAt: 0, "Steht stramm und trägt am Ende einen Stern."),
        PlantSpecies("ahorn", "Herbstahorn", .tree, .roundTree, [0xF7B877, 0xEB9A55, 0xFCD7AE, 0xDC8443, 0xE5646B],
                     unlockAt: 2, "Warme Herbstfarben, ganz ohne Herbst."),
        PlantSpecies("lavendel", "Lavendelbaum", .tree, .roundTree, [0xC6B4F0, 0xA894E0, 0xE3D8FB, 0x9179D6, 0xFFFFFF],
                     unlockAt: 4, "Duftet nach Ruhe und Konzentration."),

        PlantSpecies("tulpe", "Tulpe", .flower, .tulip, [0xF58A8A, 0xE06C70, 0xFFC2C0, 0xD9595F, 0xFFE08A],
                     unlockAt: 0, "Ein fröhlicher Kelch in Korallenrot."),
        PlantSpecies("sonnenblume", "Sonnenblume", .flower, .sunflower, [0xFFD45C, 0xF2B93B, 0xFFE9A3, 0xD99A1E, 0x9A6A45],
                     unlockAt: 1, "Dreht ihr Lächeln immer zur Sonne."),
        PlantSpecies("gaensebluemchen", "Gänseblümchen", .flower, .daisy, [0xFFFFFF, 0xE6DDEB, 0xFFFFFF, 0xC99A2E, 0xFFD45C],
                     unlockAt: 3, "Klein, weiß und immer gut gelaunt."),
        PlantSpecies("glockenblume", "Glockenblume", .flower, .bell, [0xA9B7F5, 0x8C9BE8, 0xD4DCFC, 0x7183D9, 0xFFFFFF],
                     unlockAt: 6, "Läutet ganz leise, wenn du fertig bist."),

        PlantSpecies("fliegenpilz", "Fliegenpilz", .mushroom, .toadstool, [0xE8645A, 0xC94A42, 0xF59A92, 0xC9473F, 0xFFFFFF],
                     unlockAt: 5, "Rot mit weißen Punkten – nur zum Anschauen!"),
        PlantSpecies("steinpilz", "Steinpilz", .mushroom, .porcini, [0xC08A5B, 0x9C6B3E, 0xDDB48B, 0x9A6A40, 0xF3E6D0],
                     unlockAt: 8, "Gemütlich, braun und standfest."),
        PlantSpecies("leuchtpilz", "Leuchtpilz", .mushroom, .glowshroom, [0x7FD9E0, 0x4FB7C2, 0xBFF1F4, 0x3FA9B3, 0xBFFAFF],
                     unlockAt: 12, "Leuchtet sanft – besonders im Dunkelmodus."),

        PlantSpecies("kristallbaum", "Kristallbaum", .special, .crystal, [0xA8D8F5, 0x84BDE6, 0xE1F3FD, 0x5C9FD1, 0xD7C6F7],
                     unlockAt: 15, "Funkelnde Kristalle statt Blätter."),
        PlantSpecies("regenbogenbaum", "Regenbogenbaum", .special, .rainbow, [0xF7B6C8, 0xC9B6F2, 0xFFFFFF, 0x8E7BD6, 0xFFFFFF],
                     unlockAt: 20, "Jedes Blätterbüschel in einer anderen Farbe."),

        PlantSpecies("eisblume", "Eisblume", .seasonal, .crystal, [0xDDF1FB, 0xB9DCEF, 0xFFFFFF, 0x6FA9C9, 0xC9E6F7],
                     month: 1, "Wächst nur, wenn es draußen klirrt."),
        PlantSpecies("winterling", "Winterling", .seasonal, .daisy, [0xFFE066, 0xF0C63C, 0xFFF2A8, 0xD9A51E, 0xF2A93B],
                     month: 2, "Gelber Farbtupfer im letzten Schnee."),
        PlantSpecies("krokus", "Krokus", .seasonal, .tulip, [0xB59AE8, 0x957AD6, 0xDCCBF7, 0x7D62C4, 0xFFD45C],
                     month: 3, "Schiebt sich als Erster durch den Schnee."),
        PlantSpecies("osterglocke", "Osterglocke", .seasonal, .bell, [0xFFE066, 0xF2C53D, 0xFFF3B0, 0xD9A51E, 0xFFFFFF],
                     month: 4, "Läutet den Frühling ein."),
        PlantSpecies("apfelbluete", "Apfelblüte", .seasonal, .roundTree, [0xA9DDA0, 0x86C47C, 0xD3F0CC, 0x5BAE6C, 0xFFE3EC],
                     month: 5, "Frisches Grün mit zartrosa Blüten."),
        PlantSpecies("mohn", "Mohnblume", .seasonal, .daisy, [0xF0564A, 0xD23F36, 0xFF9A8F, 0xC9372F, 0xFFD45C],
                     month: 6, "Leuchtend rot am Wegesrand."),
        PlantSpecies("kornblume", "Kornblume", .seasonal, .daisy, [0x6F9BEA, 0x4F7CD6, 0xBBD2FA, 0x436FCB, 0xFFE9A3],
                     month: 7, "So blau wie der Sommerhimmel."),
        PlantSpecies("zitrone", "Zitronenbaum", .seasonal, .roundTree, [0x9BD67F, 0x79BE60, 0xC9EDB6, 0x5AA846, 0xFFE14D],
                     month: 8, "Trägt kleine Sonnen als Früchte."),
        PlantSpecies("pflaume", "Pflaumenbaum", .seasonal, .roundTree, [0x8CCB8E, 0x6BB174, 0xBFE6BF, 0x57A066, 0x8A5FBF],
                     month: 9, "Süße lila Früchte zum Schulanfang."),
        PlantSpecies("pfifferling", "Pfifferling", .seasonal, .porcini, [0xF6B544, 0xE0942B, 0xFFD98A, 0xD9861E, 0xFBE3B0],
                     month: 10, "Goldgelb und nur im Herbst zu finden."),
        PlantSpecies("nebelpilz", "Nebelpilz", .seasonal, .glowshroom, [0xB9A9E6, 0x9684D1, 0xDDD3F7, 0x8570C4, 0xE2D9FF],
                     month: 11, "Schimmert im Novembernebel."),
        PlantSpecies("christbaum", "Christbäumchen", .seasonal, .festive, [0x4FA06E, 0x3B8757, 0x86C9A0, 0x2F7A4C, 0xFFD66B],
                     month: 12, "Geschmückt mit bunten Kugeln."),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func find(_ id: String?) -> PlantSpecies {
        id.flatMap { byID[$0] } ?? all[0]
    }

    /// Plants saved before species could be chosen only stored a seed; this reproduces their old look.
    static func legacyID(seed: Double) -> String {
        let order = ["minze", "kirsche", "tanne", "ahorn", "lavendel"]
        return order[min(order.count - 1, max(0, Int(seed * Double(order.count))))]
    }
}
