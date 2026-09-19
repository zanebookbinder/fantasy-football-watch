import SwiftUI

/// One starter: position badge, name, live points, and the ESPN-style stat line
/// beneath. The stat line arrives pre-formatted from the Lambda.
struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Slot and pro team stack into one narrow column so the stat line
            // gets the width it needs -- a QB's is long enough to wrap three
            // times otherwise.
            VStack(spacing: 2) {
                SlotBadge(slot: player.slot)
                Text(player.proTeam)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(player.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let badge = player.injuryBadge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(player.isOut ? .red : .orange)
                    }
                }

                // A QB with rushing yards produces the longest line there is
                // ("20/31, 248 yd, 3 TD · 14 car, 69 yd, 2 TD"), and it has to
                // fit without truncating on the smallest watch.
                Text(player.statLineOrPlaceholder)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.points(player.points))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // A player who has not kicked off yet shows a 0.00 that
                    // means nothing; dim it so it reads as "not yet".
                    .foregroundStyle(player.hasPlayed ? .primary : .secondary)
                Text(Format.projected(player.projected))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(player.slot) \(player.name), \(player.proTeam), "
                + "\(Format.points(player.points)) points"
        )
        .accessibilityValue(player.statLineOrPlaceholder)
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
