import SwiftUI

/// One starter: position badge, name, live points, and the ESPN-style stat line
/// beneath. The stat line arrives pre-formatted from the Lambda.
struct PlayerRow: View {
    let player: Player

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
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(player.slot) \(player.name), \(player.proTeam), "
                + "\(Format.points(player.points)) points"
        )
        .accessibilityValue(player.subtitle)
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

#Preview {
    List {
        ForEach(SamplePayload.payload.lineup(for: .me)) { player in
            PlayerRow(player: player)
        }
    }
}
