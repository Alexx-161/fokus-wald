import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The island as a picture to keep or share, with its name and a few numbers underneath.
struct IslandPoster: View {
    let garden: Garden
    let island: Int

    var body: some View {
        let plants = garden.plants(on: island)
        let minutes = plants.reduce(0) { $0 + $1.minutes }
        // Always the plain daytime sky, so the caption stays readable.
        IslandThumbnail(plants: plants, decorations: garden.decorations(on: island), complete: garden.isComplete(island),
                        scene: garden.scene(for: island, timer: nil, date: nil))
            .frame(width: 1200, height: 900)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Garden.islandName(island)).font(.system(size: 46, weight: .bold, design: .rounded))
                    Text("\(plants.count) \(plants.count == 1 ? "Pflanze" : "Pflanzen") · \(TimeFormat.duration(minutes: minutes)) Fokuszeit")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .opacity(0.7)
                }
                .padding(44)
            }
            .overlay(alignment: .bottomTrailing) {
                Label("Fokus-Wald", systemImage: "leaf.fill")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .opacity(0.7)
                    .padding(44)
            }
            .foregroundStyle(Theme.ink)
    }
}

@MainActor
enum IslandExport {
    static func png(garden: Garden, island: Int) -> Data? {
        let renderer = ImageRenderer(content: IslandPoster(garden: garden, island: island))
        renderer.scale = 2
        #if os(macOS)
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        #else
        return renderer.uiImage?.pngData()
        #endif
    }

    /// Mac: asks where to save the picture. iPhone/iPad: opens the share sheet.
    static func share(garden: Garden, island: Int) {
        guard let data = png(garden: garden, island: island) else { return }
        let name = "\(Garden.islandName(island)) – Fokus-Wald.png"
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name
        panel.title = "Insel als Bild sichern"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? data.write(to: url, options: .atomic)) != nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }
        var presenter = root
        while let next = presenter.presentedViewController { presenter = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = presenter.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY,
                                                                 width: 1, height: 1)
        presenter.present(sheet, animated: true)
        #endif
    }
}
