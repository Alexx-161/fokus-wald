import SwiftUI

enum PlantCategory: String, CaseIterable, Identifiable {
    case tree, flower, mushroom, special

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tree: return "Bäume"
        case .flower: return "Blumen"
        case .mushroom: return "Pilze"
        case .special: return "Besondere"
        }
    }

    var symbol: String {
        switch self {
        case .tree: return "tree.fill"
        case .flower: return "camera.macro"
        case .mushroom: return "umbrella.fill"
        case .special: return "sparkles"
        }
    }
}

struct PlantSpecies: Identifiable {
    enum Kind { case roundTree, pine, rainbow, crystal, tulip, sunflower, daisy, bell, toadstool, porcini, glowshroom }

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
    let blurb: String

    private init(_ id: String, _ name: String, _ category: PlantCategory, _ kind: Kind,
                 _ colors: [UInt32], unlockAt: Int, _ blurb: String) {
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
        self.blurb = blurb
    }

    /// Relative size on the island, so flowers and mushrooms stay smaller than trees.
    var islandScale: Double {
        switch category {
        case .tree: return 1.0
        case .special: return 1.08
        case .flower: return 0.72
        case .mushroom: return 0.64
        }
    }

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
