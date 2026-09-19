"""Stat-line formatting, checked against the examples in the design document."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.statlines import build_stat_line  # noqa: E402

# Read verbatim out of this league's week-2 response.
JOSH_ALLEN = {
    "0": 31.0, "1": 20.0, "3": 248.0, "4": 3.0,
    "23": 14.0, "24": 69.0, "25": 2.0,
}
KHALIL_SHAKIR = {"53": 3.0, "42": 38.0, "58": 6.0}
JARED_GOFF = {"0": 38.0, "1": 26.0, "3": 327.0, "4": 4.0, "23": 3.0, "24": 7.0}


def test_qb_passing_and_rushing():
    assert build_stat_line("QB", JOSH_ALLEN) == (
        "20/31, 248 yd, 3 TD · 14 car, 69 yd, 2 TD"
    )


def test_qb_without_rushing_touchdowns():
    assert build_stat_line("QB", JARED_GOFF) == (
        "26/38, 327 yd, 4 TD · 3 car, 7 yd"
    )


def test_qb_interceptions_appended_only_when_thrown():
    assert "INT" not in build_stat_line("QB", JOSH_ALLEN)
    with_pick = dict(JOSH_ALLEN, **{"20": 2.0})
    assert build_stat_line("QB", with_pick).startswith(
        "20/31, 248 yd, 3 TD, 2 INT"
    )


def test_receiver_line():
    assert build_stat_line("WR", KHALIL_SHAKIR) == "3 rec, 38 yd"


def test_receiver_with_touchdown():
    scored = dict(KHALIL_SHAKIR, **{"53": 7.0, "42": 69.0, "43": 1.0})
    assert build_stat_line("WR", scored) == "7 rec, 69 yd, 1 TD"


def test_running_back_leads_with_rushing():
    stats = {"23": 18, "24": 92, "25": 1, "53": 3, "42": 20, "58": 4}
    assert build_stat_line("RB", stats) == "18 car, 92 yd, 1 TD · 3 rec, 20 yd"


def test_kicker_line():
    assert build_stat_line("K", {"83": 3, "84": 3, "86": 2, "87": 2}) == (
        "3/3 FG, 2/2 XP"
    )


def test_defense_line():
    stats = {"120": 10, "99": 2, "95": 1, "104": 1}
    assert build_stat_line("D/ST", stats) == "10 PA, 2 sack, 1 INT, 1 TD"


def test_zero_stats_produce_no_line():
    assert build_stat_line("WR", {}) == ""
    assert build_stat_line("RB", {"23": 0, "24": 0}) == ""


def test_whole_numbers_lose_their_decimal_point():
    assert build_stat_line("WR", {"53": 4.0, "42": 51.0}) == "4 rec, 51 yd"


def test_fumble_lost_is_appended():
    stats = dict(KHALIL_SHAKIR, **{"72": 1.0})
    assert build_stat_line("WR", stats) == "3 rec, 38 yd · 1 FUM"
