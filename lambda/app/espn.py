"""HTTP access to ESPN: the private league read, and the public NFL scoreboard.

Uses urllib only, so the deployment package has no third-party dependencies.
"""

import json
import logging
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


def fetch_game_states(season, week):
    """proTeamId -> 'pre' | 'live' | 'final' for every team playing this week.

    Best-effort: a scoreboard failure degrades the stat lines' gameState rather
    than failing the whole request, so it never takes the score down with it.
    """
    query = urllib.parse.urlencode(
        {"week": week, "seasontype": 2, "year": season}
    )
    url = f"{C.SCOREBOARD_URL}?{query}"
    mapping = {}
    try:
        data = _get_json(url, {"User-Agent": C.BROWSER_UA}, SCOREBOARD_TIMEOUT)
    except Exception as exc:  # noqa: BLE001 - deliberately non-fatal
        log.warning("scoreboard lookup failed, falling back: %s", exc)
        return mapping

    states = {"pre": "pre", "in": "live", "post": "final"}
    for event in data.get("events") or []:
        state = ((event.get("status") or {}).get("type") or {}).get("state")
        state = states.get(state)
        if not state:
            continue
        for competition in event.get("competitions") or []:
            for competitor in competition.get("competitors") or []:
                team_id = (competitor.get("team") or {}).get("id")
                try:
                    mapping[int(team_id)] = state
                except (TypeError, ValueError):
                    continue
    return mapping
