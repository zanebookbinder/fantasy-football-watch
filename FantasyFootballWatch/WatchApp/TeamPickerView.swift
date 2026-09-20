import SwiftUI

/// The "my team" picker: shown once on first launch, and again whenever the
/// team is changed from the bottom of the matchup screen.
struct TeamPickerView: View {
    @Bindable var model: MatchupModel
    /// Nil on first launch; set when reached from the settings row, so it can
    /// dismiss itself again.
    var onDismiss: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(onDismiss == nil ? "Pick your team" : "Change team")
                    .font(.headline)
                Text("Your matchup is shown every week.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                if model.isLoadingTeams && model.leagueTeams.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else if model.leagueTeams.isEmpty {
                    Text("Couldn't load the league. Pull down to retry.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.leagueTeams) { team in
                        Button {
                            Task {
                                await model.select(team)
                                onDismiss?()
                            }
                        } label: {
                            TeamRow(
                                team: team,
                                isSelected: team.id == model.selectedTeamId
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 22)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea(.container, edges: .top)
        .task { await model.loadTeams() }
        .refreshable { await model.loadTeams() }
    }
}

private struct TeamRow: View {
    let team: LeagueTeam
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(team.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 2)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 9))
    }

    private var subtitle: String? {
        let parts = [team.abbrev, team.record].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#if DEBUG
#Preview {
    TeamPickerView(model: .preview())
}
#endif
