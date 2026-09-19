"""Collapse ESPN's ~1.5 MB league response into the compact watch payload.

The output shape is the frozen contract between the Lambda and the watch app
(design doc, "Response data model"). Keep it stable; the watch decodes it
directly into Codable structs.
"""

from datetime import datetime, timezone

from . import constants as C
from .statlines import build_stat_line

# Order starters the way a fantasy lineup card reads, rather than the arbitrary
# order ESPN returns roster entries in.
SLOT_DISPLAY_ORDER = [0, 1, 2, 3, 4, 5, 6, 23, 7, 16, 17, 18, 19]


def _round(value, places=2):
    if value is None:
        return None
    try:
        return round(float(value), places)
    except (TypeError, ValueError):
        return None


def _team_names(league):
    """teamId -> display name, falling back to the abbreviation then the id."""
    names = {}
    for team in league.get("teams") or []:
        team_id = team.get("id")
        name = (team.get("name") or "").strip()
        if not name:
            location = (team.get("location") or "").strip()
            nickname = (team.get("nickname") or "").strip()
            name = " ".join(p for p in (location, nickname) if p)
        names[team_id] = name or team.get("abbrev") or f"Team {team_id}"
    return names


def _find_matchup(league, team_id, matchup_period):
    for matchup in league.get("schedule") or []:
        if matchup.get("matchupPeriodId") != matchup_period:
            continue
        home = matchup.get("home") or {}
        away = matchup.get("away") or {}
        if team_id in (home.get("teamId"), away.get("teamId")):
            if home.get("teamId") == team_id:
                return home, away
            return away, home
    return None, None


def _split_for(player, scoring_period, stat_source_id):
    """The stat split ESPN uses for actuals (source 0) or projections (1)."""
    for split in player.get("stats") or []:
        if (
            split.get("statSourceId") == stat_source_id
            and split.get("scoringPeriodId") == scoring_period
        ):
            return split
    return None


def _build_player(entry, side, scoring_period, game_states):
    pool = entry.get("playerPoolEntry") or {}
    player = pool.get("player") or {}

    slot = C.LINEUP_SLOTS.get(entry.get("lineupSlotId"), "")
    position = C.POSITIONS.get(player.get("defaultPositionId"), slot)
    pro_team_id = player.get("proTeamId") or 0
    pro_team = C.PRO_TEAMS.get(pro_team_id, "FA")

    actual = _split_for(player, scoring_period, 0)
    projection = _split_for(player, scoring_period, 1)
    raw_stats = (actual or {}).get("stats") or {}

    # A player with a real stat split has certainly started; otherwise trust the
    # NFL scoreboard, and fall back to "pre" when the team has no game (bye).
    game_state = game_states.get(pro_team_id)
    if game_state is None:
        game_state = "live" if raw_stats else "pre"
    elif game_state == "pre" and raw_stats:
        game_state = "live"

    injury = entry.get("injuryStatus") or player.get("injuryStatus") or "NORMAL"

    return {
        "name": player.get("fullName") or "Unknown",
        "slot": slot,
        "position": position,
        "proTeam": pro_team,
        "gameState": game_state,
        "points": _round(pool.get("appliedStatTotal"), 2) or 0.0,
        "projected": _round((projection or {}).get("appliedTotal"), 1),
        "statLine": build_stat_line(position, raw_stats),
        "injury": None if injury in ("NORMAL", "ACTIVE") else injury,
        "side": side,
        "_order": (
            SLOT_DISPLAY_ORDER.index(entry.get("lineupSlotId"))
            if entry.get("lineupSlotId") in SLOT_DISPLAY_ORDER
            else len(SLOT_DISPLAY_ORDER)
        ),
    }


def _starters(team_side, side, scoring_period, game_states):
    roster = team_side.get("rosterForCurrentScoringPeriod") or {}
    entries = roster.get("entries")
    if not entries:
        # ESPN omits the live roster once a matchup period is finalized.
        roster = team_side.get("rosterForMatchupPeriod") or {}
        entries = roster.get("entries") or []

    players = [
        _build_player(entry, side, scoring_period, game_states)
        for entry in entries
        if entry.get("lineupSlotId") not in C.BENCH_SLOTS
    ]
    players.sort(key=lambda p: (p["_order"], p["name"]))
    for player in players:
        player.pop("_order", None)
    return players


def _team_summary(team_side, names):
    projected = team_side.get("totalProjectedPointsLive")
    if projected is None:
        projected = team_side.get("totalProjectedPoints")
    return {
        "team": names.get(team_side.get("teamId"), "—"),
        "live": _round(team_side.get("totalPointsLive"), 2) or 0.0,
        "projected": _round(projected, 1),
        "winProb": _round(team_side.get("winProbability"), 2),
    }


def build_payload(league, team_id, game_states=None, fetched_at=None):
    """Build the compact payload for ``team_id`` from a raw league response."""
    game_states = game_states or {}
    fetched_at = fetched_at or datetime.now(timezone.utc)
    updated = fetched_at.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    status = league.get("status") or {}
    matchup_period = status.get("currentMatchupPeriod")
    scoring_period = league.get("scoringPeriodId") or status.get(
        "latestScoringPeriod"
    )

    mine, theirs = _find_matchup(league, team_id, matchup_period)
    if mine is None:
        # Between weeks, or a bye in the fantasy schedule.
        return {
            "state": "no_matchup",
            "week": matchup_period,
            "updated": updated,
            "me": None,
            "opp": None,
            "players": [],
        }

    names = _team_names(league)
    players = _starters(mine, "me", scoring_period, game_states)
    players += _starters(theirs, "opp", scoring_period, game_states)

    return {
        "state": "ok",
        "week": matchup_period,
        "updated": updated,
        "me": _team_summary(mine, names),
        "opp": _team_summary(theirs, names),
        "players": players,
    }
