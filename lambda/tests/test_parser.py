"""Parser checks against a captured week-2 response from the real league."""

import json
import os
import sys
from datetime import datetime, timezone

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.parser import build_payload  # noqa: E402

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "league-week2.json")
TEAM_ID = 7


@pytest.fixture(scope="module")
def league():
    if not os.path.exists(FIXTURE):
        pytest.skip(
            "capture a league response first: "
            "python lambda/tools/capture_fixture.py <path-to-raw.json>"
        )
    with open(FIXTURE) as handle:
        return json.load(handle)


# Shaped like what fetch_game_states returns, with real week-2 fixtures.
GAME_STATES = {
    2: {"state": "final", "opponent": "DET", "isAway": False,
        "kickoff": "2026-09-18T00:15:00Z"},
    8: {"state": "final", "opponent": "BUF", "isAway": True,
        "kickoff": "2026-09-18T00:15:00Z"},
    25: {"state": "pre", "opponent": "MIA", "isAway": False,
         "kickoff": "2026-09-20T20:25:00Z"},
    33: {"state": "pre", "opponent": "CLE", "isAway": True,
         "kickoff": "2026-09-20T17:00:00Z"},
}


@pytest.fixture(scope="module")
def payload(league):
    # BUF final, SF yet to kick off -- exercises both scoreboard branches.
    game_states = GAME_STATES
    return build_payload(
        league,
        TEAM_ID,
        game_states=game_states,
        fetched_at=datetime(2026, 9, 19, 17, 40, tzinfo=timezone.utc),
    )


def test_contract_shape(payload):
    assert set(payload) == {
        "state", "week", "updated", "leagueSize", "me", "opp", "players",
    }
    assert payload["state"] == "ok"
    assert payload["week"] == 2
    assert payload["updated"] == "2026-09-19T17:40:00Z"


def test_reads_the_live_total_not_the_finalized_one(payload):
    # totalPoints stays 0.0 until ESPN finalizes; the app must show the live field.
    assert payload["me"]["live"] == 47.62
    assert payload["opp"]["live"] == -0.1


def test_team_names(payload):
    assert payload["me"]["team"] == "The Christian Faith"
    assert payload["opp"]["team"].startswith("Team")


def test_projected_points_and_win_probability(payload):
    assert payload["me"]["projected"] == 142.6
    assert payload["opp"]["projected"] == 108.6
    assert payload["me"]["winProb"] == 0.69
    assert payload["opp"]["winProb"] == 0.31
    assert round(payload["me"]["winProb"] + payload["opp"]["winProb"], 2) == 1.0


def test_lineup_progress_travels_with_the_score(payload):
    # A 47-0 lead reads like a blowout until you know what is left to play.
    me = payload["me"]
    assert me["toPlay"] + me["playing"] + me["done"] == 9
    assert me["done"] == 2  # Allen and Shakir, both BUF/DET, are final
    assert me["playing"] == 0
    assert me["toPlay"] == 7
    # Projections of the seven who have not kicked off.
    assert me["remaining"] > 0


def test_remaining_only_counts_players_yet_to_play(payload):
    yet_to_play = [
        p for p in payload["players"]
        if p["side"] == "me" and p["gameState"] == "pre"
    ]
    expected = round(sum(p["projected"] or 0 for p in yet_to_play), 1)
    assert payload["me"]["remaining"] == expected


def test_week_ranking_covers_the_whole_league(payload):
    assert payload["leagueSize"] == 10
    # 47.62 is the top score in the league this week; -0.10 is the bottom.
    assert payload["me"]["rank"] == 1
    assert payload["opp"]["rank"] == 10


def test_record_and_seed(payload):
    assert payload["me"]["record"] == "1-0"
    assert payload["me"]["seed"] == 1


def test_both_lineups_are_present_and_tagged(payload):
    sides = {p["side"] for p in payload["players"]}
    assert sides == {"me", "opp"}
    assert len([p for p in payload["players"] if p["side"] == "me"]) == 9


def test_bench_players_are_excluded(payload):
    assert all(p["slot"] not in ("BE", "IR") for p in payload["players"])


def test_starters_are_in_lineup_order(payload):
    mine = [p["slot"] for p in payload["players"] if p["side"] == "me"]
    assert mine == ["QB", "RB", "RB", "WR", "WR", "TE", "FLEX", "D/ST", "K"]


def test_player_fields(payload):
    allen = next(p for p in payload["players"] if p["name"] == "Josh Allen")
    assert allen["slot"] == "QB"
    assert allen["proTeam"] == "BUF"
    assert allen["points"] == 40.82
    assert allen["projected"] == 22.7
    assert allen["statLine"] == "20/31, 248 yd, 3 TD · 14 car, 69 yd, 2 TD"
    assert allen["side"] == "me"


def test_game_clock_rides_along_for_live_games(league):
    states = dict(GAME_STATES)
    states[2] = {
        "state": "live", "opponent": "DET", "isAway": False,
        "kickoff": "2026-09-18T00:15:00Z", "clock": "Q3 4:12",
    }
    payload = build_payload(league, TEAM_ID, game_states=states)
    allen = next(p for p in payload["players"] if p["name"] == "Josh Allen")
    assert allen["clock"] == "Q3 4:12"

    kittle = next(p for p in payload["players"] if p["name"] == "George Kittle")
    assert kittle["clock"] is None  # not kicked off


def test_opponent_and_kickoff_ride_along(payload):
    kittle = next(p for p in payload["players"] if p["name"] == "George Kittle")
    assert kittle["opponent"] == "MIA"  # SF at home
    assert kittle["kickoff"] == "2026-09-20T20:25:00Z"

    henry = next(p for p in payload["players"] if p["name"] == "Derrick Henry")
    assert henry["opponent"] == "@CLE"  # BAL on the road
    assert henry["kickoff"] == "2026-09-20T17:00:00Z"


def test_kickoff_is_absent_when_the_scoreboard_says_nothing(league):
    payload = build_payload(league, TEAM_ID, game_states={})
    for player in payload["players"]:
        assert player["opponent"] is None
        assert player["kickoff"] is None


def test_a_bare_state_string_is_still_accepted(league):
    payload = build_payload(league, TEAM_ID, game_states={2: "final"})
    allen = next(p for p in payload["players"] if p["name"] == "Josh Allen")
    assert allen["gameState"] == "final"
    assert allen["opponent"] is None


def test_game_state_from_the_scoreboard(payload):
    allen = next(p for p in payload["players"] if p["name"] == "Josh Allen")
    assert allen["gameState"] == "final"
    kittle = next(p for p in payload["players"] if p["name"] == "George Kittle")
    assert kittle["gameState"] == "pre"  # SF has not kicked off
    assert kittle["statLine"] == ""


def test_a_scoreboard_miss_falls_back_to_having_stats(league):
    payload = build_payload(league, TEAM_ID, game_states={})
    allen = next(p for p in payload["players"] if p["name"] == "Josh Allen")
    assert allen["gameState"] == "live"
    kittle = next(p for p in payload["players"] if p["name"] == "George Kittle")
    assert kittle["gameState"] == "pre"


def test_stats_override_a_stale_pre_from_the_scoreboard(league):
    payload = build_payload(
        league, TEAM_ID,
        game_states={2: {"state": "pre", "opponent": "DET", "isAway": False,
                         "kickoff": "2026-09-18T00:15:00Z"}},
    )
    allen = next(p for p in payload["players"] if p["name"] == "Josh Allen")
    assert allen["gameState"] == "live"


def test_numbers_are_numbers(payload):
    for player in payload["players"]:
        assert isinstance(player["points"], (int, float))
        assert player["projected"] is None or isinstance(
            player["projected"], (int, float)
        )


def test_payload_stays_small(payload):
    assert len(json.dumps(payload)) < 8000


def test_missing_matchup_yields_an_empty_state(league):
    payload = build_payload(league, team_id=999)
    assert payload["state"] == "no_matchup"
    assert payload["players"] == []
    assert payload["me"] is None
    assert payload["leagueSize"] is None
