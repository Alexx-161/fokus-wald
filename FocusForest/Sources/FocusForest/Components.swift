import SwiftUI

// Small building blocks shared by the Mac app and the iPhone/iPad app.

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(color))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(tint ?? Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.track))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ChipButtonStyle: ButtonStyle {
    var selected: Bool
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? color : Theme.track))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct RoundIconButtonStyle: ButtonStyle {
    var size: CGFloat
    var active: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(active == nil ? Theme.ink : .white)
            .frame(width: size, height: size)
            .background(Circle().fill(active ?? Theme.track))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
    }
}

/// Mini sky-and-island preview of a theme.
struct ThemeSwatch: View {
    let theme: AppTheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [theme.skyTop, theme.skyBottom], startPoint: .top, endPoint: .bottom)
                Ellipse().fill(theme.earth).frame(width: w * 0.62, height: h * 0.42).offset(y: h * 0.12)
                Ellipse().fill(theme.grass).frame(width: w * 0.68, height: h * 0.3).offset(y: -h * 0.08)
                PlantIcon(species: PlantSpecies.find(theme.id == "sakura" ? "kirsche" : theme.id == "herbst" ? "ahorn" : theme.id == "winter" ? "tanne" : "minze"))
                    .frame(width: h * 0.48, height: h * 0.48)
                    .offset(y: -h * 0.17)
            }
            .frame(width: w, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, theme.scheme ?? .light)
    }
}
