import SwiftUI

/// The full-detail surface: matchup header plus every starter and stat line.
struct MatchupView: View {
    @Bindable var model: MatchupModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.payload?.state {
                case .ok:
                    lineupPages
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var navigationTitle: String {
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

    /// The matchup header is the same on both sides, so it stays put; only the
    /// roster below it pages. The page dots under it are the team indicator.
    private var lineupPages: some View {
        VStack(spacing: 0) {
            MatchupHeaderView(
                me: model.payload?.me,
                opp: model.payload?.opp,
                leagueSize: model.payload?.leagueSize
            )
            .padding(.horizontal, 6)

            TabView(selection: $model.side) {
                lineupList(for: .me)
                    .tag(Side.me)
                lineupList(for: .opp)
                    .tag(Side.opp)
            }
            .tabViewStyle(.page)
        }
    }

    private func lineupList(for side: Side) -> some View {
        List {
            Section {
                ForEach(model.payload?.lineup(for: side) ?? []) { player in
                    PlayerRow(player: player)
                }
            } header: {
                Text(model.team(for: side)?.team ?? "Lineup")
                    .lineLimit(1)
            } footer: {
                freshnessFooter
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
        .accessibilityLabel(
            side == .me ? "Your lineup" : "Your opponent's lineup"
        )
    }

    @ViewBuilder
    private var freshnessFooter: some View {
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
        // Clear of the page dots, which float over the bottom of the TabView.
        .padding(.bottom, 14)
    }

    /// "1st of 10 · 1-0" — season context, which belongs below the live
    /// numbers rather than competing with them for permanent header space.
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
