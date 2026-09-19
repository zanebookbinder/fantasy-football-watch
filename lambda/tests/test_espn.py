"""The two ESPN hosts want opposite clients; guard that it stays that way."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app import constants as C  # noqa: E402
from app import espn  # noqa: E402


def test_the_scoreboard_does_not_get_the_browser_user_agent(monkeypatch):
    # site.api 403s browser UAs even with full browser headers, and the
    # fallback is plausible enough to hide it. Pin the distinction.
    seen = {}

    def fake_get(url, headers, timeout):
        seen["ua"] = headers.get("User-Agent")
        return {"events": []}

    monkeypatch.setattr(espn, "_get_json", fake_get)
    espn.fetch_game_states(2026, 2)

    assert seen["ua"] == C.SCOREBOARD_UA
    assert seen["ua"] != C.BROWSER_UA


def test_the_league_read_does_get_the_browser_user_agent(monkeypatch):
    seen = {}

    def fake_get(url, headers, timeout):
        seen.update(headers)
        return {}

    monkeypatch.setattr(espn, "_get_json", fake_get)
    espn.fetch_league("123", 2026, "{swid}", "s2")

    assert seen["User-Agent"] == C.BROWSER_UA
    assert "SWID={swid}" in seen["Cookie"]


def test_kickoff_times_get_seconds_added():
    # ESPN sends '2026-09-25T00:15Z'; strict ISO 8601 parsers reject it.
    assert espn._normalize_kickoff("2026-09-25T00:15Z") == "2026-09-25T00:15:00Z"
    assert espn._normalize_kickoff("2026-09-25T00:15:00Z") == "2026-09-25T00:15:00Z"
    assert espn._normalize_kickoff(None) is None
    assert espn._normalize_kickoff("nonsense") is None


def test_a_scoreboard_failure_is_survivable(monkeypatch):
    def boom(url, headers, timeout):
        raise RuntimeError("403")

    monkeypatch.setattr(espn, "_get_json", boom)
    assert espn.fetch_game_states(2026, 2) == {}


def test_game_clock_formatting():
    clock = espn._game_clock
    assert clock({"period": 3, "displayClock": "4:12"}) == "Q3 4:12"
    assert clock({"period": 5, "displayClock": "1:20"}) == "OT 1:20"
    assert clock(
        {"type": {"name": "STATUS_HALFTIME"}, "period": 2}
    ) == "Half"
    assert clock({"period": 0, "displayClock": "0:00"}) is None


def test_clock_is_only_attached_to_live_games(monkeypatch):
    event = {
        "date": "2026-09-20T17:00Z",
        "status": {
            "type": {"state": "pre", "name": "STATUS_SCHEDULED"},
            "period": 0, "displayClock": "0:00",
        },
        "competitions": [{"competitors": [
            {"homeAway": "home", "team": {"id": "2", "abbreviation": "BUF"}},
            {"homeAway": "away", "team": {"id": "8", "abbreviation": "DET"}},
        ]}],
    }
    monkeypatch.setattr(espn, "_get_json", lambda *a: {"events": [event]})
    mapping = espn.fetch_game_states(2026, 2)
    assert mapping[2]["clock"] is None
    assert mapping[2]["opponent"] == "DET"
    assert mapping[8]["isAway"] is True
