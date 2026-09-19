"""HTTP access to ESPN: the private league read, and the public NFL scoreboard.

Uses urllib only, so the deployment package has no third-party dependencies.
"""

import json
import logging
from datetime import datetime, timezone
import urllib.error
import urllib.parse
import urllib.request

from . import constants as C

log = logging.getLogger(__name__)

LEAGUE_TIMEOUT = 8
SCOREBOARD_TIMEOUT = 5


class AuthExpired(Exception):
    """ESPN rejected the cookies (401/403) -- time to re-grab them."""


class UpstreamError(Exception):
    """ESPN returned something unusable."""


def _get_json(url, headers, timeout):
    request = urllib.request.Request(url, headers=headers, method="GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read()
    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        # ESPN has previously started serving HTML error pages from a moved host.
        raise UpstreamError(f"non-JSON response from {url}") from exc


def league_url(league_id, season):
    path = C.LEAGUE_PATH.format(season=season, league_id=league_id)
    query = urllib.parse.urlencode([("view", v) for v in C.LEAGUE_VIEWS])
    return f"{C.LEAGUE_HOST}{path}?{query}"


def fetch_league(league_id, season, swid, espn_s2):
    """Fetch the raw league response. Raises AuthExpired / UpstreamError."""
    url = league_url(league_id, season)
    headers = {
        "Cookie": f"SWID={swid}; espn_s2={espn_s2}",
        "User-Agent": C.BROWSER_UA,
        "Accept": "application/json",
        "X-Fantasy-Source": "kona",
        "X-Fantasy-Platform": "kona-PROD",
    }
    try:
        return _get_json(url, headers, LEAGUE_TIMEOUT)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise AuthExpired(f"ESPN returned {exc.code}") from exc
        raise UpstreamError(f"ESPN returned {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise UpstreamError(f"could not reach ESPN: {exc.reason}") from exc


def _normalize_kickoff(raw):
    """ESPN sends '2026-09-25T00:15Z' -- no seconds, which strict ISO 8601
    parsers (Swift's included) reject. Re-emit it with seconds."""
    if not raw:
        return None
    try:
        parsed = datetime.strptime(raw, "%Y-%m-%dT%H:%MZ")
    except ValueError:
        try:
            parsed = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            return None
    return parsed.replace(tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _game_clock(status):
    """"Q3 4:12", "Half", "OT 1:20" -- how much football is left to care about."""
    if (status.get("type") or {}).get("name") == "STATUS_HALFTIME":
        return "Half"
    period = status.get("period") or 0
    display = (status.get("displayClock") or "").strip()
    if 1 <= period <= 4:
        label = f"Q{period}"
    elif period >= 5:
        label = "OT"
    else:
        return None
    return f"{label} {display}".strip() or None


def fetch_game_states(season, week):
    """proTeamId -> this week's game for that team.

    Each value is ``{"state", "opponent", "isAway", "kickoff"}``: the state is
    'pre' | 'live' | 'final', and the rest lets the watch show "@SF Sun 1pm"
    for a player who has not kicked off instead of a meaningless 0.00.

    Best-effort: a scoreboard failure degrades gameState and hides kickoff
    times rather than failing the whole request, so it never takes the score
    down with it.
    """
    query = urllib.parse.urlencode(
        {"week": week, "seasontype": 2, "year": season}
    )
    url = f"{C.SCOREBOARD_URL}?{query}"
    mapping = {}
    try:
        data = _get_json(url, {"User-Agent": C.SCOREBOARD_UA}, SCOREBOARD_TIMEOUT)
    except Exception as exc:  # noqa: BLE001 - deliberately non-fatal
        # Logged at error level on purpose: the fallback produces plausible
        # output, so a silent warning let a broken scoreboard call go unnoticed
        # in production once already.
        log.error("scoreboard lookup failed, approximating gameState: %s", exc)
        return mapping

    states = {"pre": "pre", "in": "live", "post": "final"}
    for event in data.get("events") or []:
        status = event.get("status") or {}
        state = states.get((status.get("type") or {}).get("state"))
        if not state:
            continue
        kickoff = _normalize_kickoff(event.get("date"))
        clock = _game_clock(status) if state == "live" else None

        for competition in event.get("competitions") or []:
            competitors = competition.get("competitors") or []
            if len(competitors) != 2:
                continue
            for competitor in competitors:
                team = competitor.get("team") or {}
                try:
                    team_id = int(team.get("id"))
                except (TypeError, ValueError):
                    continue
                other = next(c for c in competitors if c is not competitor)
                opponent = (other.get("team") or {}).get("abbreviation")
                mapping[team_id] = {
                    "state": state,
                    "opponent": opponent,
                    "isAway": competitor.get("homeAway") == "away",
                    "kickoff": kickoff,
                    "clock": clock,
                }
    return mapping
