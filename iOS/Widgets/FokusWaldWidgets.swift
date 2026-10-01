import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FokusWaldWidgets: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
    }
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(light: 0xFBF7F0, dark: 0x1D1E1B))
                .activitySystemActionForegroundColor(Color(light: 0x3E3A34, dark: 0xEEE9E0))
        } dynamicIsland: { context in
            let species = PlantSpecies.find(context.attributes.speciesID)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PlantBadge(species: species, seed: context.attributes.seed)
                        .frame(width: 54, height: 54)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(context: context)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(species.main)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(species.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        SessionProgress(context: context, tint: species.main)
                        Text(statusText(context, species))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                PlantBadge(species: species, seed: context.attributes.seed)
                    .frame(width: 24, height: 24)
            } compactTrailing: {
                CountdownText(context: context)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(species.main)
                    .frame(maxWidth: 48)
            } minimal: {
                PlantBadge(species: species, seed: context.attributes.seed)
                    .frame(width: 22, height: 22)
            }
            .keylineTint(species.main)
        }
    }
}

private func isDone(_ context: ActivityViewContext<FocusActivityAttributes>) -> Bool {
    context.state.finished || context.isStale
}

private func statusText(_ context: ActivityViewContext<FocusActivityAttributes>, _ species: PlantSpecies) -> String {
    if isDone(context) { return "\(species.name) ist fertig!" }
    if context.state.pausedRemaining != nil { return "Pausiert – deine Pflanze wartet auf dich" }
    return "\(species.name) wächst …"
}

private struct LockScreenView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        let species = PlantSpecies.find(context.attributes.speciesID)
        HStack(spacing: 14) {
            PlantBadge(species: species, seed: context.attributes.seed)
                .frame(width: 60, height: 60)
                .background(Circle().fill(species.light.opacity(0.35)))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(statusText(context, species))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    CountdownText(context: context)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .frame(maxWidth: 96, alignment: .trailing)
                }
                SessionProgress(context: context, tint: species.deep)
            }
        }
        .padding(16)
        .foregroundStyle(Color(light: 0x3E3A34, dark: 0xEEE9E0))
    }
}

/// The fully grown plant as a small picture; drawn with the same painter as the app.
private struct PlantBadge: View {
    let species: PlantSpecies
    let seed: Double

    var body: some View {
        Canvas { ctx, size in
            let unit = min(size.width, size.height / 0.7)
            PlantPainter.draw(ctx, species: species, base: CGPoint(x: size.width / 2, y: size.height * 0.95),
                              unit: unit, progress: 1, seed: seed, time: 0, ground: false, detail: unit > 40)
        }
    }
}

private struct CountdownText: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        Group {
            if isDone(context) {
                Text("Fertig")
            } else if let remaining = context.state.pausedRemaining {
                Text(TimeFormat.clock(remaining))
            } else {
                Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private struct SessionProgress: View {
    let context: ActivityViewContext<FocusActivityAttributes>
    let tint: Color

    var body: some View {
        Group {
            if isDone(context) {
                ProgressView(value: 1)
            } else if let remaining = context.state.pausedRemaining {
                ProgressView(value: max(0, min(1, 1 - remaining / max(1, context.state.total))))
            } else {
                ProgressView(timerInterval: context.state.startDate...context.state.endDate, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.linear)
        .tint(tint)
    }
}
