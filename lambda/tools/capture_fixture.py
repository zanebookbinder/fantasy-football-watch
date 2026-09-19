#!/usr/bin/env python3
"""Trim a raw ESPN league response down to a test fixture.

The real response is ~1.5 MB of rankings, ownership and every scoring period of
the season. The parser touches a small slice of that, so this keeps only the
slice -- real data, small enough to commit.

    python lambda/tools/capture_fixture.py ~/Downloads/fantasy-data.json

Writes lambda/tests/fixtures/league-week2.json.
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

from app import constants as C  # noqa: E402

DEFAULT_OUT = os.path.join(HERE, "..", "tests", "fixtures", "league-week2.json")

# Fields the parser reads off a player; everything else is dropped.
PLAYER_FIELDS = (
    "id", "fullName", "firstName", "lastName", "defaultPositionId",
    "proTeamId", "injuryStatus", "injured", "jersey",
)
SPLIT_FIELDS = (
    "appliedTotal", "scoringPeriodId", "seasonId", "statSourceId",
    "statSplitTypeId", "stats",
)


def trim_player(player, scoring_period):
    trimmed = {k: player[k] for k in PLAYER_FIELDS if k in player}
    trimmed["stats"] = [
        {k: split[k] for k in SPLIT_FIELDS if k in split}
        for split in player.get("stats") or []
        if split.get("scoringPeriodId") == scoring_period
        and split.get("statSourceId") in (0, 1)
    ]
    return trimmed


def trim_side(side, scoring_period):
    trimmed = {
        k: side[k]
        for k in (
            "teamId", "totalPoints", "totalPointsLive", "totalProjectedPoints",
            "totalProjectedPointsLive", "winProbability",
        )
        if k in side
    }
    roster = side.get("rosterForCurrentScoringPeriod") or {}
    trimmed["rosterForCurrentScoringPeriod"] = {
        "entries": [
            {
                "lineupSlotId": entry.get("lineupSlotId"),
                "playerId": entry.get("playerId"),
                "injuryStatus": entry.get("injuryStatus"),
                "playerPoolEntry": {
                    "appliedStatTotal": (
                        entry.get("playerPoolEntry") or {}
                    ).get("appliedStatTotal"),
                    "player": trim_player(
                        (entry.get("playerPoolEntry") or {}).get("player") or {},
                        scoring_period,
                    ),
                },
            }
            for entry in roster.get("entries") or []
        ]
    }
    return trimmed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="raw league JSON from ESPN")
    parser.add_argument("-o", "--out", default=DEFAULT_OUT)
    parser.add_argument("--team-id", type=int, default=C.DEFAULT_TEAM_ID)
    args = parser.parse_args()

    with open(args.source) as handle:
        league = json.load(handle)

    scoring_period = league.get("scoringPeriodId")
    matchup_period = (league.get("status") or {}).get("currentMatchupPeriod")

    schedule = []
    for matchup in league.get("schedule") or []:
        if matchup.get("matchupPeriodId") != matchup_period:
            continue
        home, away = matchup.get("home") or {}, matchup.get("away") or {}
        if args.team_id not in (home.get("teamId"), away.get("teamId")):
            continue
        schedule.append(
            {
                "id": matchup.get("id"),
                "matchupPeriodId": matchup_period,
                "winner": matchup.get("winner"),
                "home": trim_side(home, scoring_period),
                "away": trim_side(away, scoring_period),
            }
        )

    fixture = {
        "id": league.get("id"),
        "seasonId": league.get("seasonId"),
        "scoringPeriodId": scoring_period,
        "status": {
            k: (league.get("status") or {}).get(k)
            for k in ("currentMatchupPeriod", "latestScoringPeriod", "isActive")
        },
        "teams": [
            {"id": t.get("id"), "name": t.get("name"), "abbrev": t.get("abbrev")}
            for t in league.get("teams") or []
        ],
        "schedule": schedule,
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as handle:
        json.dump(fixture, handle, indent=1, sort_keys=True)
        handle.write("\n")
    size = os.path.getsize(args.out)
    print(f"wrote {args.out} ({size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
