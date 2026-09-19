import SwiftUI

/// Both totals, the projected finish, and the win-probability bar — the whole
/// matchup at a glance, which is goal one.
struct MatchupHeaderView: View {
    let me: TeamScore?
    let opp: TeamScore?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                totals(for: me, alignment: .leading)
                Spacer(minLength: 4)
                totals(for: opp, alignment: .trailing)
            }

            winProbabilityBar

            HStack {
                projection(me)
                Spacer()
                projection(opp)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func totals(
        for team: TeamScore?, alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(team.map { Format.points($0.live) } ?? "—")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(leaderTint(for: team))
            Text(team?.team ?? "—")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(
            maxWidth: .infinity,
            alignment: alignment == .leading ? .leading : .trailing
        )
    }

    /// Only tint the side that is actually ahead, so colour carries meaning.
    private func leaderTint(for team: TeamScore?) -> Color {
        guard let team, let me, let opp else { return .primary }
        if me.live == opp.live { return .primary }
        let leaderIsMe = me.live > opp.live
        let isLeader = (team.team == me.team) == leaderIsMe
        return isLeader ? .green : .primary
    }

    @ViewBuilder
    private var winProbabilityBar: some View {
        if let myProb = me?.winProb {
            VStack(spacing: 2) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.tertiary)
                        Capsule()
                            .fill(myProb >= 0.5 ? Color.green : Color.orange)
                            .frame(width: geometry.size.width * myProb)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(me?.winPercentText ?? "")
                    Spacer()
                    Text(opp?.winPercentText ?? "")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Win probability \(me?.winPercentText ?? "unknown")"
            )
        }
    }

    private func projection(_ team: TeamScore?) -> some View {
        Text("proj \(Format.projected(team?.projected))")
            .monospacedDigit()
    }
}

#Preview {
    MatchupHeaderView(
        me: SamplePayload.payload.me,
        opp: SamplePayload.payload.opp
    )
    .padding(.horizontal)
}
