"""Lambda entry point: GET /score behind a Function URL.

Authenticate the caller, serve from cache, fetch ESPN on a miss, parse to the
compact model, and surface auth failures cleanly (design doc, "AWS Lambda proxy
design").
"""

import base64
import hmac
import json
import logging
import os
from datetime import datetime, timezone

from . import constants as C
from . import espn, secrets
from .cache import KeyedCache
from .parser import build_payload, list_teams

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

LEAGUE_ID = os.environ.get("LEAGUE_ID", C.DEFAULT_LEAGUE_ID)
TEAM_ID = int(os.environ.get("TEAM_ID", C.DEFAULT_TEAM_ID))
SEASON = int(os.environ.get("SEASON", C.DEFAULT_SEASON))
CACHE_TTL = float(os.environ.get("CACHE_TTL_SECONDS", "20"))

# Module-level, so both survive across warm invocations. Keyed by team, because
# the watch now chooses which team's matchup it wants.
_cache = KeyedCache(ttl_seconds=CACHE_TTL)
_teams_cache = KeyedCache(ttl_seconds=600.0)


def _respond(status, body):
    return {
        "statusCode": status,
        "headers": {
            "content-type": "application/json",
            # The payload is personal and time-sensitive; let the watch and the
            # Lambda's own cache be the only things holding it.
            "cache-control": "no-store",
        },
        "body": json.dumps(body, separators=(",", ":")),
    }


def _key_matches(event, header, env_var):
    expected = os.environ.get(env_var, "")
    if not expected:
        # Fail closed: an unset key must never mean an open endpoint.
        log.error("%s is not set; refusing every request", env_var)
        return False
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    return hmac.compare_digest(headers.get(header, ""), expected)


def _authorized(event):
    if os.environ.get("REQUIRE_API_KEY", "true").lower() == "false":
        return True
    return _key_matches(event, "x-api-key", "CLIENT_API_KEY")


def _admin_authorized(event):
    """Writes use their own key.

    The read key lives in the watch app's Info.plist, on a device that can be
    lost; it must not also be able to rewrite the ESPN session.
    """
    return _key_matches(event, "x-admin-key", "ADMIN_API_KEY")


def _json_body(event):
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError("body must be a JSON object")
    return parsed


def _requested_team(event):
    """The team the watch asked for, falling back to the configured default."""
    params = event.get("queryStringParameters") or {}
    raw = params.get("teamId") or params.get("teamid")
    if raw in (None, ""):
        return TEAM_ID
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def _path(event):
    return event.get("rawPath") or event.get("path") or "/"


def _method(event):
    http = (event.get("requestContext") or {}).get("http") or {}
    return http.get("method") or event.get("httpMethod") or "GET"


def _empty(state, updated=None):
    return {
        "state": state,
        "week": None,
        "updated": updated
        or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "leagueSize": None,
        "me": None,
        "opp": None,
        "players": [],
    }


def _fetch_league():
    swid, espn_s2 = secrets.get_cookies()
    return espn.fetch_league(LEAGUE_ID, SEASON, swid, espn_s2)


def _fetch_payload(team_id):
    """Fetch and parse a fresh payload for one team, or raise."""
    league = _fetch_league()

    week = league.get("scoringPeriodId") or (league.get("status") or {}).get(
        "latestScoringPeriod"
    )
    game_states = espn.fetch_game_states(SEASON, week) if week else {}

    return build_payload(
        league,
        team_id,
        game_states=game_states,
        fetched_at=datetime.now(timezone.utc),
    )


def _handle_teams(event):
    """GET /teams -- the league's rosters of record, for the "my team" picker.

    Cached far longer than a score: names and records barely move, and this is
    only read when someone opens the picker.
    """
    cached = _teams_cache.get("all")
    if cached is not None:
        return _respond(200, cached)

    try:
        payload = {"state": "ok", "teams": list_teams(_fetch_league())}
    except espn.AuthExpired:
        secrets.reset()
        return _respond(200, {"state": "auth_expired", "teams": []})
    except Exception as exc:  # noqa: BLE001
        log.exception("could not list teams: %s", exc)
        last_good = _teams_cache.last_good("all")
        if last_good is not None:
            return _respond(200, last_good)
        return _respond(502, {"state": "upstream_error", "teams": []})

    _teams_cache.put("all", payload)
    return _respond(200, payload)


def _handle_cookie_write(event):
    """POST /cookies -- rotate the ESPN session without AWS credentials.

    Validates the pair against ESPN *before* writing, so a bad paste leaves a
    working secret alone. Cookie values are never logged.
    """
    if not _admin_authorized(event):
        return _respond(403, {"state": "forbidden"})

    try:
        body = _json_body(event)
    except (ValueError, TypeError, base64.binascii.Error):
        return _respond(400, {"state": "bad_request"})

    espn_s2 = (body.get("espn_s2") or "").strip()
    if not espn_s2:
        return _respond(400, {"state": "bad_request"})

    swid = secrets.normalize_swid(body.get("SWID") or body.get("swid"))
    if not swid:
        # SWID is an account GUID that does not change; reuse the stored one.
        try:
            swid = secrets.get_cookies()[0]
        except Exception:  # noqa: BLE001
            return _respond(400, {"state": "bad_request"})

    try:
        espn.fetch_league(LEAGUE_ID, SEASON, swid, espn_s2)
    except espn.AuthExpired:
        log.warning("rejected a cookie write: ESPN did not accept the pair")
        return _respond(400, {"state": "rejected"})
    except Exception as exc:  # noqa: BLE001
        log.exception("could not reach ESPN to validate: %s", exc)
        return _respond(502, {"state": "upstream_error"})

    try:
        secrets.put_cookies(swid, espn_s2)
    except Exception as exc:  # noqa: BLE001
        log.exception("could not write the secret: %s", exc)
        return _respond(500, {"state": "write_failed"})

    # This container recovers now rather than after the TTL; the others drop
    # their cookies on their own next 401.
    _cache.clear()
    _teams_cache.clear()
    log.info("ESPN cookies rotated")
    return _respond(200, {"state": "ok"})


def handler(event, context=None):
    if _path(event) == "/cookies" and _method(event) == "POST":
        return _handle_cookie_write(event)

    if _method(event) not in ("GET", "HEAD"):
        return _respond(405, {"state": "method_not_allowed"})

    path = _path(event)
    if path not in ("/score", "/teams", "/", ""):
        return _respond(404, {"state": "not_found"})

    if not _authorized(event):
        return _respond(403, {"state": "forbidden"})

    if path == "/teams":
        return _handle_teams(event)

    team_id = _requested_team(event)
    if team_id is None:
        return _respond(400, {"state": "bad_request"})

    cached = _cache.get(team_id)
    if cached is not None:
        return _respond(200, cached)

    try:
        payload = _fetch_payload(team_id)
    except espn.AuthExpired:
        # Cookies have rolled. Tell the watch in a way it can render kindly,
        # with HTTP 200 so it is not confused with a transport failure.
        log.warning("ESPN rejected the stored cookies; refresh the secret")
        secrets.reset()
        payload = _empty("auth_expired")
        _cache.put(team_id, payload)
        return _respond(200, payload)
    except Exception as exc:  # noqa: BLE001 - every upstream failure lands here
        log.exception("upstream failure: %s", exc)
        last_good = _cache.last_good(team_id)
        if last_good is not None:
            # A slightly stale score beats an error; `updated` keeps it honest.
            return _respond(200, last_good)
        return _respond(502, _empty("upstream_error"))

    _cache.put(team_id, payload)
    return _respond(200, payload)


# Alias matching the SAM template's Handler: app.handler.lambda_handler
lambda_handler = handler
