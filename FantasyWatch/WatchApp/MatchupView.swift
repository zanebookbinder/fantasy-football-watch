import SwiftUI

/// The full-detail surface: matchup header plus every starter and stat line.
struct MatchupView: View {
    @Bindable var model: MatchupModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.payload?.state {
                case .ok:
                    lineupList
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
        .refreshable { await model.refresh() }
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

    private var lineupList: some View {
        List {
            Section {
                MatchupHeaderView(
                    me: model.payload?.me,
                    opp: model.payload?.opp
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(model.lineup) { player in
                    PlayerRow(player: player)
                }
            } header: {
                sideHeader
            } footer: {
                freshnessFooter
            }
        }
        .listStyle(.carousel)
    }

    private var sideHeader: some View {
        Button {
            model.toggleSide()
        } label: {
            HStack {
                Text(model.focusedTeam?.team ?? "Lineup")
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Switches between your lineup and your opponent's")
    }

    @ViewBuilder
    private var freshnessFooter: some View {
        if let updated = model.payload?.updated {
            HStack(spacing: 4) {
                if model.isShowingLastGood {
                    Image(systemName: "wifi.slash")
                }
                Text("as of \(Format.staleness(since: updated))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
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
