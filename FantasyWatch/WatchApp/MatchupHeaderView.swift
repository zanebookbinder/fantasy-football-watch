import SwiftUI

/// Both totals, the projected finish, and the win-probability bar — the whole
/// matchup at a glance, which is goal one.
struct MatchupHeaderView: View {
    let me: TeamScore?
    let opp: TeamScore?
    var leagueSize: Int?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                totals(for: me, alignment: .leading)
                Spacer(minLength: 4)
                totals(for: opp, alignment: .trailing)
            }

            winProbabilityBar

            // Projection and what is left to play share a line: the header no
            // longer scrolls away, so each row it costs is a row of roster.
            HStack(alignment: .firstTextBaseline) {
                summary(me, alignment: .leading)
                Spacer(minLength: 4)
                summary(opp, alignment: .trailing)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 1)
        .padding(.bottom, 4)
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

    /// "proj 142.6 · 7 to play" — the projection and what is left to come.
    private func summary(
        _ team: TeamScore?, alignment: HorizontalAlignment
    ) -> some View {
        let projection = "proj \(Format.projected(team?.projected))"
        let text = [projection, team?.progressText]
            .compactMap { $0 }
            .joined(separator: " · ")
        return Text(text)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(
                maxWidth: .infinity,
                alignment: alignment == .leading ? .leading : .trailing
            )
    }
}

#Preview {
    MatchupHeaderView(
        me: SamplePayload.payload.me,
        opp: SamplePayload.payload.opp,
        leagueSize: SamplePayload.payload.leagueSize
    )
    .padding(.horizontal)
}
