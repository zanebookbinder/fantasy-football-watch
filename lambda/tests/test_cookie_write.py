"""POST /cookies -- rotating the ESPN session without AWS credentials."""

import importlib
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


@pytest.fixture
def mod(monkeypatch):
    monkeypatch.setenv("CLIENT_API_KEY", "read-key-read-key-read")
    monkeypatch.setenv("ADMIN_API_KEY", "admin-key-admin-key-ad")
    monkeypatch.setenv("ESPN_SECRET_ID", "test/secret")
    from app import handler as module

    importlib.reload(module)
    return module


@pytest.fixture
def written(mod, monkeypatch):
    """Capture writes instead of touching Secrets Manager."""
    calls = []
    monkeypatch.setattr(
        mod.secrets, "put_cookies", lambda swid, s2: calls.append((swid, s2))
    )
    monkeypatch.setattr(mod.secrets, "get_cookies", lambda: ("{STORED}", "old"))
    monkeypatch.setattr(mod.espn, "fetch_league", lambda *a, **k: {"id": 1})
    return calls


def post(key="admin-key-admin-key-ad", body=None, raw=None, b64=False):
    headers = {"x-admin-key": key} if key is not None else {}
    return {
        "rawPath": "/cookies",
        "headers": headers,
        "requestContext": {"http": {"method": "POST"}},
        "body": raw if raw is not None else json.dumps(body or {}),
        "isBase64Encoded": b64,
    }


def state(response):
    return json.loads(response["body"])["state"]


def test_happy_path(mod, written):
    response = mod.handler(post(body={"espn_s2": "fresh"}))
    assert response["statusCode"] == 200
    assert state(response) == "ok"
    assert written == [("{STORED}", "fresh")]


def test_the_read_key_cannot_write(mod, written):
    # The whole point of a separate key: the watch app's key is on a device
    # that can be lost and must not be able to rewrite the session.
    response = mod.handler(post(key="read-key-read-key-read", body={"espn_s2": "x"}))
    assert response["statusCode"] == 403
    assert written == []


def test_missing_and_wrong_keys_are_refused(mod, written):
    assert mod.handler(post(key=None, body={"espn_s2": "x"}))["statusCode"] == 403
    assert mod.handler(post(key="nope", body={"espn_s2": "x"}))["statusCode"] == 403
    assert written == []


def test_fails_closed_when_no_admin_key_is_configured(mod, written, monkeypatch):
    monkeypatch.delenv("ADMIN_API_KEY", raising=False)
    assert mod.handler(post(body={"espn_s2": "x"}))["statusCode"] == 403
    assert written == []


def test_a_cookie_espn_rejects_is_not_saved(mod, written, monkeypatch):
    def boom(*a, **k):
        raise mod.espn.AuthExpired("401")

    monkeypatch.setattr(mod.espn, "fetch_league", boom)
    response = mod.handler(post(body={"espn_s2": "typo"}))

    assert response["statusCode"] == 400
    assert state(response) == "rejected"
    assert written == [], "a bad paste must leave a working secret alone"


def test_espn_being_down_does_not_save_either(mod, written, monkeypatch):
    def boom(*a, **k):
        raise mod.espn.UpstreamError("500")

    monkeypatch.setattr(mod.espn, "fetch_league", boom)
    assert mod.handler(post(body={"espn_s2": "x"}))["statusCode"] == 502
    assert written == []


def test_swid_is_optional_and_reuses_the_stored_one(mod, written):
    mod.handler(post(body={"espn_s2": "fresh"}))
    assert written[0][0] == "{STORED}"


def test_a_bare_swid_gets_its_braces(mod, written):
    mod.handler(post(body={"espn_s2": "fresh", "SWID": "ABC-123"}))
    assert written[0][0] == "{ABC-123}"


def test_lowercase_swid_key_is_accepted(mod, written):
    mod.handler(post(body={"espn_s2": "fresh", "swid": "{ABC-123}"}))
    assert written[0][0] == "{ABC-123}"


def test_empty_or_malformed_bodies(mod, written):
    assert state(mod.handler(post(body={}))) == "bad_request"
    assert state(mod.handler(post(body={"espn_s2": "   "}))) == "bad_request"
    assert state(mod.handler(post(raw="not json"))) == "bad_request"
    assert state(mod.handler(post(raw='"a string"'))) == "bad_request"
    assert written == []


def test_base64_bodies_are_decoded(mod, written):
    import base64 as b64mod

    encoded = b64mod.b64encode(json.dumps({"espn_s2": "fresh"}).encode()).decode()
    assert mod.handler(post(raw=encoded, b64=True))["statusCode"] == 200
    assert written[0][1] == "fresh"


def test_a_successful_write_clears_the_cached_payload(mod, written):
    mod._cache.put(7, {"state": "auth_expired"})
    assert mod._cache.get(7) is not None
    mod.handler(post(body={"espn_s2": "fresh"}))
    assert mod._cache.get(7) is None, "should recover now, not after the TTL"


def test_get_on_cookies_is_not_a_write(mod, written):
    event = post(body={"espn_s2": "x"})
    event["requestContext"]["http"]["method"] = "GET"
    assert mod.handler(event)["statusCode"] == 404
    assert written == []
