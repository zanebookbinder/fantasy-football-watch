import SwiftUI

/// The full-detail surface: matchup header plus every starter and stat line.
struct MatchupView: View {
    @Bindable var model: MatchupModel

    /// Which roster the horizontal pager is resting on.
    @State private var pagedSide: Side? = .me

    /// Presented from the settings row at the bottom of the scroll.
    @State private var isChangingTeam = false
    @State private var isConfirmingTeamChange = false

    // No NavigationStack: its top bar pinned the week label in place and blurred
    // whatever scrolled under it. The label is ordinary content now, so it sits
    // level with the clock and scrolls away with everything else.
    var body: some View {
        content
            .sheet(isPresented: $isChangingTeam) {
                TeamPickerView(model: model) { isChangingTeam = false }
            }
    }

    @ViewBuilder
    private var content: some View {
        // Nothing can be fetched until a team has been picked, so the picker is
        // the whole screen on a first launch.
        if model.needsTeamSelection {
            TeamPickerView(model: model)
        } else {
            matchupStates
        }
    }

    @ViewBuilder
    private var matchupStates: some View {
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

                sideIndicator
                rosterPager
                footer
                teamSettingsRow
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
        // Keeps the Digital Crown with the vertical scroll: without this the
        // pager takes crown focus and rotating it flips teams.
        .focusable(false)
        .onChange(of: pagedSide) { _, side in
            if let side, model.side != side { model.side = side }
        }
        .onChange(of: model.side) { _, side in
            // Keeps the pager honest when something else moves the selection,
            // such as the widget's deep link.
            if pagedSide != side { pagedSide = side }
        }
    }

    /// Which roster is showing, and the one control that flips it. Double tap
    /// triggers this as the primary action on the watches that support it.
    private var sideIndicator: some View {
        Button {
            model.toggleSide()
        } label: {
            HStack(spacing: 5) {
                Text(model.team(for: model.side)?.team ?? "Lineup")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                ForEach([Side.me, Side.opp], id: \.self) { side in
                    Circle()
                        .fill(side == model.side ? AnyShapeStyle(.secondary)
                                                 : AnyShapeStyle(.tertiary))
                        .frame(width: 5, height: 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .primaryHandGesture()
        .accessibilityLabel(
            model.side == .me ? "Showing your lineup" : "Showing your opponent's lineup"
        )
        .accessibilityHint("Switches to the other team")
    }

    private func rosterColumn(for side: Side) -> some View {
        VStack(alignment: .leading, spacing: 5) {

            ForEach(model.payload?.lineup(for: side) ?? []) { player in
                Button {
                    model.toggleExpanded(player)
                } label: {
                    PlayerRow(
                        player: player,
                        change: model.change(for: player),
                        isExpanded: model.isExpanded(player)
                    )
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(
                        .fill.tertiary,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
                .buttonStyle(.plain)
            }

            // Belongs to the team on screen, so it rides the swipe with the
            // roster rather than always describing your own team.
            standing(for: side)
        }
        .containerRelativeFrame(.horizontal)
        .accessibilityLabel(
            side == .me ? "Your lineup" : "Your opponent's lineup"
        )
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let updated = model.payload?.updated {
                HStack(spacing: 4) {
                    if model.isShowingLastGood {
                        Image(systemName: "wifi.slash")
                    }
                    Text("Data as of \(Format.staleness(since: updated))")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    /// Bottom of the scroll, out of the way of the live numbers: switching
    /// teams throws away every cached score and change baseline, so it asks
    /// first.
    private var teamSettingsRow: some View {
        Button {
            isConfirmingTeamChange = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.2")
                    .font(.system(size: 10))
                VStack(alignment: .leading, spacing: 0) {
                    Text("My team")
                        .font(.system(size: 12, weight: .medium))
                    if let name = model.selectedTeamName {
                        Text(name)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .confirmationDialog(
            "Change team?",
            isPresented: $isConfirmingTeamChange,
            titleVisibility: .visible
        ) {
            Button("Change team") { isChangingTeam = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This reloads the whole matchup and clears what's changed since your last view.")
        }
    }

    /// Today's scoring on top, the season underneath — two different things
    /// that read as one when they share a line.
    @ViewBuilder
    private func standing(for side: Side) -> some View {
        if let team = model.team(for: side) {
            VStack(alignment: .leading, spacing: 0) {
                if let scoring = team.scoringRankText {
                    Text(scoring)
                }
                if let league = team.leagueStandingText {
                    Text(league)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 1)
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

#if DEBUG
#Preview("Matchup") {
    MatchupView(model: .preview())
}

#Preview("Opponent") {
    MatchupView(model: .preview(side: .opp))
}

#Preview("Reconnect") {
    MatchupView(model: .preview(SamplePayload.payload.with(state: .authExpired)))
}
#endif

private extension View {
    /// Binds the watch's double-tap gesture to this control, where the
    /// hardware supports it. Gated because the deployment target is watchOS 10
    /// and the gesture shortcut arrived in 11.
    @ViewBuilder
    func primaryHandGesture() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}
