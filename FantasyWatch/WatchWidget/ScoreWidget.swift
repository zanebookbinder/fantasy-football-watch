import SwiftUI
import WidgetKit

/// The glance surface. Widgets are small, so this shows the score, not the
/// roster — the app exists for the full breakdown.
struct ScoreWidget: Widget {
    static let kind = "FantasyScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ScoreProvider()) { entry in
            ScoreWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(AppConfiguration.deepLinkScheme)://matchup"))
        }
        .configurationDisplayName("Fantasy Score")
        .description("Your live matchup score and win probability.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCircular,
            .accessoryCorner,
        ])
    }
}

struct ScoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScoreEntry

    private var me: TeamScore? { entry.payload.me }
    private var opp: TeamScore? { entry.payload.opp }

    var body: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryCircular, .accessoryCorner:
            circular
        default:
            rectangular
        }
    }

    // MARK: - Families

    private var inline: some View {
        Text(inlineText)
    }

    private var inlineText: String {
        guard let me, let opp else { return "Fantasy —" }
        return "\(Format.compactPoints(me.live)) – \(Format.compactPoints(opp.live))"
    }

    private var circular: some View {
        Gauge(value: me?.winProb ?? 0, in: 0...1) {
            Text("W%")
        } currentValueLabel: {
            Text(Format.compactPoints(me?.live ?? 0))
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.green)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch entry.payload.state {
            case .authExpired:
                Text("Reconnect ESPN")
                    .font(.headline)
                Text("Cookies expired")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .noMatchup:
                Text("No matchup")
                    .font(.headline)
                Text("Nothing scheduled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            default:
                scoreLine
                detailLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive(false)
    }

    private var scoreLine: some View {
        HStack(spacing: 4) {
            Text(Format.compactPoints(me?.live ?? 0))
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
                .widgetAccentable()
            Text("–")
                .foregroundStyle(.secondary)
            Text(Format.compactPoints(opp?.live ?? 0))
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
            Spacer(minLength: 0)
            if let winPercent = me?.winPercentText {
                Text(winPercent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        if let top = entry.payload.topScorer, top.points > 0 {
            Text("\(top.name) \(Format.compactPoints(top.points))")
                .font(.caption2)
                .lineLimit(1)
        } else if let me, let projected = me.projected {
            Text("proj \(Format.projected(projected))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Text(opp?.team ?? "")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    ScoreWidget()
} timeline: {
    ScoreProvider.placeholderEntry
}

#Preview("Inline", as: .accessoryInline) {
    ScoreWidget()
} timeline: {
    ScoreProvider.placeholderEntry
}

#Preview("Circular", as: .accessoryCircular) {
    ScoreWidget()
} timeline: {
    ScoreProvider.placeholderEntry
}
