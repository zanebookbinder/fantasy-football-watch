import SwiftUI

/// The full-detail surface: matchup header plus every starter and stat line.
struct MatchupView: View {
    @Bindable var model: MatchupModel

    /// Which roster the horizontal pager is resting on.
    @State private var pagedSide: Side? = .me

    // No NavigationStack: its top bar pinned the week label in place and blurred
    // whatever scrolled under it. The label is ordinary content now, so it sits
    // level with the clock and scrolls away with everything else.
    var body: some View {
        switch model.payload?.state {
        case .ok:
            matchup
        case .authExpired:
            StatusView(
                symbol: "key.slash",
                title: "Reconnect",
                message: "ESPN signed the proxy out. Refresh the cookies in Secrets Manager.",
                tint: .orange
            )
        case .noMatchup:
            StatusView(
                symbol: "calendar",
                title: "No matchup",
                message: "Nothing scheduled this week.",
                tint: .secondary
            )
        case .upstreamError:
            StatusView(
                symbol: "exclamationmark.icloud",
                title: "ESPN unavailable",
                message: "Couldn't read the league. Trying again shortly.",
                tint: .orange
            )
        case nil:
            initialState
        }
    }

    private var weekText: String {
        guard let week = model.payload?.week else { return "Fantasy" }
        return "Week \(week)"
    }

    @ViewBuilder
    private var initialState: some View {
        if let message = model.errorMessage {
            StatusView(
                symbol: "wifi.exclamationmark",
                title: "Offline",
                message: message,
                tint: .orange
            )
        } else {
            ProgressView("Loading matchup…")
        }
    }

    /// One vertical scroll over everything, so the header scrolls away like any
    /// other content, with a horizontal pager nested inside it that moves only
    /// the roster.
    private var matchup: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                Text(weekText)
                    .font(.caption)
                    .foregroundStyle(.green)

                MatchupHeaderView(
                    me: model.payload?.me,
                    opp: model.payload?.opp,
                    leagueSize: model.payload?.leagueSize
                )

                rosterPager
                footer
            }
            .padding(.horizontal, 6)
            // Hand-measured so the week label lands level with the clock. The
            // safe area is ignored because its inset is far taller than a
            // caption needs, and paying it put a dead band under the label.
            .padding(.top, 22)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// A paging horizontal scroll rather than a TabView: it takes its height
    /// from its content, so it can sit inside the vertical scroll instead of
    /// claiming a fixed slice of the screen.
    private var rosterPager: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                rosterColumn(for: .me).id(Side.me)
                rosterColumn(for: .opp).id(Side.opp)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pagedSide)
        .scrollIndicators(.hidden)
        .onChange(of: pagedSide) { _, side in
            if let side, model.side != side { model.side = side }
        }
        .onChange(of: model.side) { _, side in
            // Keeps the pager honest when something else moves the selection,
            // such as the widget's deep link.
            if pagedSide != side { pagedSide = side }
        }
    }

    private func rosterColumn(for side: Side) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(model.team(for: side)?.team ?? "Lineup")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                // Which of the two rosters this is, now that there are no
                // page dots to say so.
                Image(systemName: side == .me ? "circle.fill" : "circle")
                    .font(.system(size: 5))
                    .foregroundStyle(.tertiary)
                Image(systemName: side == .me ? "circle" : "circle.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(.tertiary)
            }

            ForEach(model.payload?.lineup(for: side) ?? []) { player in
                PlayerRow(player: player)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        .fill.tertiary,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
            }
        }
        .containerRelativeFrame(.horizontal)
        .accessibilityLabel(
            side == .me ? "Your lineup" : "Your opponent's lineup"
        )
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let standing = standingText {
                Text(standing)
            }
            if let updated = model.payload?.updated {
                HStack(spacing: 4) {
                    if model.isShowingLastGood {
                        Image(systemName: "wifi.slash")
                    }
                    Text("as of \(Format.staleness(since: updated))")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    /// "1st of 10 · 1-0" — season context, which belongs below the live
    /// numbers rather than competing with them for header space.
    private var standingText: String? {
        guard let me = model.payload?.me else { return nil }
        var parts: [String] = []
        if let rank = me.rankText {
            parts.append(
                model.payload?.leagueSize.map { "\(rank) of \($0)" } ?? rank
            )
        }
        if let record = me.record { parts.append(record) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Shared empty / error presentation, so every non-ok state reads the same way.
struct StatusView: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}

#Preview("Matchup") {
    MatchupView(model: .preview())
}

#Preview("Opponent") {
    MatchupView(model: .preview(side: .opp))
}

#Preview("Reconnect") {
    MatchupView(model: .preview(SamplePayload.payload.with(state: .authExpired)))
}
