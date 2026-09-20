"""Static ESPN lookup tables.

Everything ESPN-specific and brittle lives here so a mid-season ID change is a
one-line edit in one file (design doc, "Stat line construction").
"""

# --- League identity -------------------------------------------------------
# Overridable via environment variables; these are the defaults for this repo's
# single personal league.
DEFAULT_LEAGUE_ID = "1896305934"
DEFAULT_TEAM_ID = 7
DEFAULT_SEASON = 2026

LEAGUE_HOST = "https://lm-api-reads.fantasy.espn.com"
LEAGUE_PATH = "/apis/v3/games/ffl/seasons/{season}/segments/0/leagues/{league_id}"
LEAGUE_VIEWS = ("mMatchupScore", "mScoreboard", "mRoster", "mTeam")

# Public, cookie-free NFL scoreboard, used to derive real pre/live/final state.
SCOREBOARD_URL = (
    "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"
)

# The two ESPN endpoints want OPPOSITE clients, which is not a typo:
#
#   lm-api-reads (private fantasy)  401s anything that is not browser-shaped.
#   site.api     (public scoreboard) 403s browser UAs -- even with a full set of
#                                    Accept / Referer / Sec-Fetch-* headers --
#                                    and serves plain clients happily.
#
# Sending the browser UA to both looks tidy and silently breaks the scoreboard.
BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
)
SCOREBOARD_UA = "curl/8.7.1"

# --- Lineup slots ----------------------------------------------------------
# lineupSlotId -> label shown in the position badge.
LINEUP_SLOTS = {
    0: "QB",
    1: "TQB",
    2: "RB",
    3: "RB/WR",
    4: "WR",
    5: "WR/TE",
    6: "TE",
    7: "OP",
    8: "DT",
    9: "DE",
    10: "LB",
    11: "DL",
    12: "CB",
    13: "S",
    14: "DB",
    15: "DP",
    16: "D/ST",
    17: "K",
    18: "P",
    19: "HC",
    20: "BE",
    21: "IR",
    23: "FLEX",
    24: "ER",
}

# Slots that do not count toward the live total / starter list.
BENCH_SLOTS = {20, 21, 24}

# --- Positions -------------------------------------------------------------
# player.defaultPositionId -> position, which drives stat-line formatting.
POSITIONS = {
    1: "QB",
    2: "RB",
    3: "WR",
    4: "TE",
    5: "K",
    7: "P",
    9: "DT",
    10: "DE",
    11: "LB",
    12: "CB",
    13: "S",
    14: "DB",
    16: "D/ST",
}

# --- Pro teams -------------------------------------------------------------
# player.proTeamId -> abbreviation. These ids are ESPN's canonical NFL team ids,
# so the same number joins against the public scoreboard's competitor team id.
PRO_TEAMS = {
    0: "FA",
    1: "ATL",
    2: "BUF",
    3: "CHI",
    4: "CIN",
    5: "CLE",
    6: "DAL",
    7: "DEN",
    8: "DET",
    9: "GB",
    10: "TEN",
    11: "IND",
    12: "KC",
    13: "LV",
    14: "LAR",
    15: "MIA",
    16: "MIN",
    17: "NE",
    18: "NO",
    19: "NYG",
    20: "NYJ",
    21: "PHI",
    22: "ARI",
    23: "PIT",
    24: "LAC",
    25: "SF",
    26: "SEA",
    27: "TB",
    28: "WSH",
    29: "CAR",
    30: "JAX",
    33: "BAL",
    34: "HOU",
}

# --- Stat IDs --------------------------------------------------------------
# Keys are the numeric ids in player.stats[].stats. The offensive skill ids were
# read straight out of this league's own response (Josh Allen and Khalil Shakir,
# week 2) and are verified. The K and D/ST ids come from the community
# `espn-api` map and are NOT yet verified against this league -- confirm them in
# a week where a kicker and a defense have actually scored.
PASS_ATTEMPTS = "0"
PASS_COMPLETIONS = "1"
PASS_YARDS = "3"
PASS_TDS = "4"
PASS_2PT = "19"
PASS_INTS = "20"

RUSH_ATTEMPTS = "23"
RUSH_YARDS = "24"
RUSH_TDS = "25"
RUSH_2PT = "26"

RECEPTIONS = "53"
REC_YARDS = "42"
REC_TDS = "43"
REC_2PT = "44"
TARGETS = "58"

FUMBLES_LOST = "72"

# Kicking (unverified).
FG_MADE = "83"
FG_ATTEMPTED = "84"
FG_MADE_50_PLUS = "74"
XP_MADE = "86"
XP_ATTEMPTED = "87"

# Defense / special teams (unverified).
DST_POINTS_ALLOWED = "120"
DST_YARDS_ALLOWED = "127"
DST_SACKS = "99"
DST_INTERCEPTIONS = "95"
DST_FUMBLE_RECOVERIES = "96"
DST_BLOCKED_KICKS = "97"
DST_SAFETIES = "98"
DST_TD_STAT_IDS = ("101", "102", "103", "104")  # KR, PR, fumble ret, INT ret

# --- Structured stats ------------------------------------------------------
# The watch diffs a player's stats between visits to say what changed since you
# last looked, which a formatted string cannot support. Each entry is
# (payload key, stat id); only non-zero values are sent. The labels for these
# keys live on the watch, since it is the one rendering the difference.
STAT_FIELDS = (
    ("cmp", PASS_COMPLETIONS),
    ("att", PASS_ATTEMPTS),
    ("passYd", PASS_YARDS),
    ("passTd", PASS_TDS),
    ("int", PASS_INTS),
    ("car", RUSH_ATTEMPTS),
    ("rushYd", RUSH_YARDS),
    ("rushTd", RUSH_TDS),
    ("tgt", TARGETS),
    ("rec", RECEPTIONS),
    ("recYd", REC_YARDS),
    ("recTd", REC_TDS),
    ("fum", FUMBLES_LOST),
    ("fgm", FG_MADE),
    ("fga", FG_ATTEMPTED),
    ("xpm", XP_MADE),
    ("xpa", XP_ATTEMPTED),
    ("pa", DST_POINTS_ALLOWED),
    ("sack", DST_SACKS),
    ("dInt", DST_INTERCEPTIONS),
    ("fr", DST_FUMBLE_RECOVERIES),
    ("blk", DST_BLOCKED_KICKS),
    ("saf", DST_SAFETIES),
)
