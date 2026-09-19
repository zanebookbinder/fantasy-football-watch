#!/usr/bin/env python3
"""Emit the compact payload from the committed fixture.

This is the frozen contract made concrete: the watch app decodes this exact file
in previews and tests, so both halves of the project can be built independently.

    python lambda/tools/sample_payload.py -o docs/sample-payload.json
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

from app import constants as C  # noqa: E402
from app.parser import build_payload  # noqa: E402

FIXTURE = os.path.join(HERE, "..", "tests", "fixtures", "league-week2.json")
GAME_STATES = os.path.join(
    HERE, "..", "tests", "fixtures", "game-states-week2.json"
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-i", "--fixture", default=FIXTURE)
    parser.add_argument("-o", "--out", default="-")
    parser.add_argument("--team-id", type=int, default=C.DEFAULT_TEAM_ID)
    args = parser.parse_args()

    with open(args.fixture) as handle:
        league = json.load(handle)

    # The real week-2 scoreboard, captured so the sample stays deterministic.
    with open(GAME_STATES) as handle:
        game_states = {int(k): v for k, v in json.load(handle).items()}
    payload = build_payload(
        league,
        args.team_id,
        game_states=game_states,
        fetched_at=datetime(2026, 9, 19, 17, 40, tzinfo=timezone.utc),
    )

    text = json.dumps(payload, indent=2) + "\n"
    if args.out == "-":
        sys.stdout.write(text)
    else:
        with open(args.out, "w") as handle:
            handle.write(text)
        print(f"wrote {args.out} ({len(text)} bytes)")


if __name__ == "__main__":
    main()
