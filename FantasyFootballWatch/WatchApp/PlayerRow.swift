import SwiftUI

/// One starter: position badge, name, live points, and the ESPN-style stat line
/// beneath. The stat line arrives pre-formatted from the Lambda.
struct PlayerRow: View {
    let player: Player
    /// What this player has done since the last look, if anything.
    var change: PlayerChange?
    /// Whether the change detail is open.
    var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Badge, name and points share one baseline-aligned row -- stacking
            // the badge above the name left it floating oddly high.
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                SlotBadge(slot: player.slot)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }

                Text(player.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Retired as soon as the row is opened, and back only if the
                // player's score moves again.
                if change != nil {
                    Circle()
                        .fill(.blue)
                        .frame(width: 6, height: 6)
                }

                if let badge = player.injuryBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(player.isOut ? .red : .orange)
                }

                Spacer(minLength: 2)

                Text(Format.points(player.points))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // A player who has not kicked off yet shows a 0.00 that
                    // means nothing; dim it so it reads as "not yet".
                    .foregroundStyle(player.hasPlayed ? .primary : .secondary)
            }

            // The subtitle spans the full width now that nothing sits beside
            // it, so even a QB's long dual line fits in two.
            HStack(alignment: .top, spacing: 4) {
                Text(player.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                // Mid-game, the clock matters more than the projection: it is
                // the difference between a 12-point third quarter and a final.
                if let status = player.statusText {
                    Text(status)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                } else {
                    Text(Format.projected(player.projected))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            if isExpanded, let change {
                changeDetail(change)
            }
        }
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.15), value: isExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(player.slot) \(player.name), \(player.proTeam), "
                + "\(Format.points(player.points)) points"
        )
        .accessibilityValue(player.subtitle)
    }
}

extension PlayerRow {
    @ViewBuilder
    func changeDetail(_ change: PlayerChange) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(Format.signedDelta(change.points)) points since last view")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(change.isGain ? .green : .red)
            if !change.statSummary.isEmpty {
                Text(change.statSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.top, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}

struct SlotBadge: View {
    let slot: String

    var body: some View {
        Text(slot)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: 30, height: 16)
            .background(tint, in: RoundedRectangle(cornerRadius: 4))
    }

    private var tint: Color {
        switch slot {
        case "QB": return .pink
        case "RB": return .mint
        case "WR": return .cyan
        case "TE": return .orange
        case "FLEX": return .purple
        case "K": return .yellow
        case "D/ST": return .brown
        default: return .gray
        }
    }
}

#if DEBUG
#Preview {
    List {
        ForEach(SamplePayload.payload.lineup(for: .me)) { player in
            PlayerRow(player: player)
        }
    }
}
#endif
