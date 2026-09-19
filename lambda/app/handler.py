"""Lambda entry point: GET /score behind a Function URL.

Authenticate the caller, serve from cache, fetch ESPN on a miss, parse to the
compact model, and surface auth failures cleanly (design doc, "AWS Lambda proxy
design").
"""

import hmac
import json
import logging
import os
from datetime import datetime, timezone

from . import constants as C
from . import espn, secrets
from .cache import PayloadCache
from .parser import build_payload

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

LEAGUE_ID = os.environ.get("LEAGUE_ID", C.DEFAULT_LEAGUE_ID)
TEAM_ID = int(os.environ.get("TEAM_ID", C.DEFAULT_TEAM_ID))
SEASON = int(os.environ.get("SEASON", C.DEFAULT_SEASON))
CACHE_TTL = float(os.environ.get("CACHE_TTL_SECONDS", "20"))

# Module-level, so it survives across warm invocations.
_cache = PayloadCache(ttl_seconds=CACHE_TTL)


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


def _authorized(event):
    expected = os.environ.get("CLIENT_API_KEY", "")
    if os.environ.get("REQUIRE_API_KEY", "true").lower() == "false":
        return True
    if not expected:
        # Fail closed: an unset key must never mean an open endpoint.
        log.error("CLIENT_API_KEY is not set; refusing every request")
        return False
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    presented = headers.get("x-api-key", "")
    return hmac.compare_digest(presented, expected)


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
        "me": None,
        "opp": None,
        "players": [],
    }


def _fetch_payload():
    """Fetch and parse a fresh payload, or raise."""
    swid, espn_s2 = secrets.get_cookies()
    league = espn.fetch_league(LEAGUE_ID, SEASON, swid, espn_s2)

    week = league.get("scoringPeriodId") or (league.get("status") or {}).get(
        "latestScoringPeriod"
    )
    game_states = espn.fetch_game_states(SEASON, week) if week else {}

    return build_payload(
        league,
        TEAM_ID,
        game_states=game_states,
        fetched_at=datetime.now(timezone.utc),
    )


def handler(event, context=None):
    if _method(event) not in ("GET", "HEAD"):
        return _respond(405, {"state": "method_not_allowed"})

    path = _path(event)
    if path not in ("/score", "/", ""):
        return _respond(404, {"state": "not_found"})

    if not _authorized(event):
        return _respond(403, {"state": "forbidden"})

    cached = _cache.get()
    if cached is not None:
        return _respond(200, cached)

    try:
        payload = _fetch_payload()
    except espn.AuthExpired:
        # Cookies have rolled. Tell the watch in a way it can render kindly,
        # with HTTP 200 so it is not confused with a transport failure.
        log.warning("ESPN rejected the stored cookies; refresh the secret")
        secrets.reset()
        payload = _empty("auth_expired")
        _cache.put(payload)
        return _respond(200, payload)
    except Exception as exc:  # noqa: BLE001 - every upstream failure lands here
        log.exception("upstream failure: %s", exc)
        last_good = _cache.last_good
        if last_good is not None:
            # A slightly stale score beats an error; `updated` keeps it honest.
            return _respond(200, last_good)
        return _respond(502, _empty("upstream_error"))

    _cache.put(payload)
    return _respond(200, payload)


# Alias matching the SAM template's Handler: app.handler.lambda_handler
lambda_handler = handler
