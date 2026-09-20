"""Handler behaviour: auth, caching, and the documented failure states."""

import importlib
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


@pytest.fixture
def handler_module(monkeypatch):
    monkeypatch.setenv("CLIENT_API_KEY", "test-key")
    monkeypatch.setenv("CACHE_TTL_SECONDS", "20")
    from app import handler as module

    importlib.reload(module)
    return module


def request(path="/score", key="test-key", method="GET", team_id=None):
    headers = {"x-api-key": key} if key is not None else {}
    event = {
        "rawPath": path,
        "headers": headers,
        "requestContext": {"http": {"method": method}},
    }
    if team_id is not None:
        event["queryStringParameters"] = {"teamId": str(team_id)}
    return event


def body_of(response):
    return json.loads(response["body"])


def test_requires_the_api_key(handler_module):
    assert handler_module.handler(request(key="wrong"))["statusCode"] == 403
    assert handler_module.handler(request(key=None))["statusCode"] == 403


def test_fails_closed_when_no_key_is_configured(handler_module, monkeypatch):
    monkeypatch.delenv("CLIENT_API_KEY", raising=False)
    assert handler_module.handler(request())["statusCode"] == 403


def test_unknown_paths_404(handler_module):
    assert handler_module.handler(request(path="/admin"))["statusCode"] == 404


def test_non_get_is_rejected(handler_module):
    response = handler_module.handler(request(method="POST"))
    assert response["statusCode"] == 405


def test_successful_fetch_is_cached(handler_module, monkeypatch):
    calls = []
    payload = {"state": "ok", "week": 2, "players": []}
    monkeypatch.setattr(
        handler_module,
        "_fetch_payload",
        lambda team_id: calls.append(team_id) or payload,
    )

    first = handler_module.handler(request())
    second = handler_module.handler(request())

    assert first["statusCode"] == 200
    assert body_of(second) == payload
    assert len(calls) == 1, "second poll within the TTL must not hit ESPN"


def test_expired_cookies_return_auth_expired_with_http_200(
    handler_module, monkeypatch
):
    def boom(team_id):
        raise handler_module.espn.AuthExpired("401")

    monkeypatch.setattr(handler_module, "_fetch_payload", boom)
    response = handler_module.handler(request())

    assert response["statusCode"] == 200
    assert body_of(response)["state"] == "auth_expired"


def test_upstream_failure_without_history_is_a_502(handler_module, monkeypatch):
    def boom(team_id):
        raise handler_module.espn.UpstreamError("ESPN returned 500")

    monkeypatch.setattr(handler_module, "_fetch_payload", boom)
    response = handler_module.handler(request())

    assert response["statusCode"] == 502
    assert body_of(response)["state"] == "upstream_error"


def test_upstream_failure_serves_the_last_good_payload(
    handler_module, monkeypatch
):
    good = {"state": "ok", "week": 2, "updated": "2026-09-19T17:40:00Z"}
    monkeypatch.setattr(handler_module, "_fetch_payload", lambda team_id: good)
    handler_module.handler(request())
    handler_module._cache.clear()  # expire the short TTL, keep last-good

    def boom(team_id):
        raise handler_module.espn.UpstreamError("ESPN returned 500")

    monkeypatch.setattr(handler_module, "_fetch_payload", boom)
    response = handler_module.handler(request())

    assert response["statusCode"] == 200
    assert body_of(response) == good


def test_responses_are_not_cached_by_intermediaries(handler_module, monkeypatch):
    monkeypatch.setattr(
        handler_module, "_fetch_payload", lambda team_id: {"state": "ok"}
    )
    response = handler_module.handler(request())
    assert response["headers"]["cache-control"] == "no-store"


def test_team_id_defaults_to_the_configured_team(handler_module, monkeypatch):
    seen = []
    monkeypatch.setattr(
        handler_module,
        "_fetch_payload",
        lambda team_id: seen.append(team_id) or {"state": "ok"},
    )
    handler_module.handler(request())
    assert seen == [handler_module.TEAM_ID]


def test_team_id_can_be_chosen_per_request(handler_module, monkeypatch):
    seen = []
    monkeypatch.setattr(
        handler_module,
        "_fetch_payload",
        lambda team_id: seen.append(team_id) or {"state": "ok", "t": team_id},
    )
    handler_module.handler(request(team_id=12))
    assert seen == [12]


def test_each_team_caches_separately(handler_module, monkeypatch):
    seen = []
    monkeypatch.setattr(
        handler_module,
        "_fetch_payload",
        lambda team_id: seen.append(team_id) or {"state": "ok", "t": team_id},
    )
    handler_module.handler(request(team_id=7))
    handler_module.handler(request(team_id=12))
    handler_module.handler(request(team_id=7))

    # Switching teams must not evict the team you came from.
    assert seen == [7, 12]
    assert body_of(handler_module.handler(request(team_id=12)))["t"] == 12


def test_a_junk_team_id_is_rejected(handler_module, monkeypatch):
    monkeypatch.setattr(
        handler_module, "_fetch_payload", lambda team_id: {"state": "ok"}
    )
    event = request()
    event["queryStringParameters"] = {"teamId": "not-a-number"}
    assert handler_module.handler(event)["statusCode"] == 400


def test_teams_endpoint_lists_the_league(handler_module, monkeypatch):
    monkeypatch.setattr(
        handler_module,
        "_fetch_league",
        lambda: {"teams": [{"id": 7, "name": "Mine", "abbrev": "ZANE"}]},
    )
    response = handler_module.handler(request(path="/teams"))
    body = body_of(response)

    assert response["statusCode"] == 200
    assert body["state"] == "ok"
    assert body["teams"][0]["name"] == "Mine"


def test_teams_endpoint_needs_the_api_key(handler_module):
    assert handler_module.handler(
        request(path="/teams", key="wrong")
    )["statusCode"] == 403


def test_teams_endpoint_is_cached(handler_module, monkeypatch):
    calls = []
    monkeypatch.setattr(
        handler_module,
        "_fetch_league",
        lambda: calls.append(1) or {"teams": [{"id": 1, "name": "A"}]},
    )
    handler_module.handler(request(path="/teams"))
    handler_module.handler(request(path="/teams"))
    assert len(calls) == 1
