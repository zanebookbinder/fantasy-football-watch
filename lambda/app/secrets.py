"""ESPN cookie retrieval.

Cookies live in Secrets Manager and are read once per cold start, then held in a
module-level variable for the life of the warm container. They are never
returned to the client and never logged.
"""

import json
import os
import threading

_lock = threading.Lock()
_cached = None


def _from_environment():
    swid = os.environ.get("ESPN_SWID")
    espn_s2 = os.environ.get("ESPN_S2")
    if swid and espn_s2:
        return swid, espn_s2
    return None


def _from_secrets_manager(secret_id):
    import boto3  # imported lazily so tests need no AWS SDK

    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=secret_id)
    secret = json.loads(response["SecretString"])
    swid = secret.get("SWID") or secret.get("swid")
    espn_s2 = secret.get("espn_s2") or secret.get("ESPN_S2")
    if not swid or not espn_s2:
        raise RuntimeError(
            f"secret {secret_id} must contain SWID and espn_s2 keys"
        )
    return swid, espn_s2


def get_cookies():
    """Return ``(swid, espn_s2)``, cached across warm invocations."""
    global _cached
    if _cached is not None:
        return _cached
    with _lock:
        if _cached is not None:
            return _cached
        # Local development / tests can short-circuit Secrets Manager.
        cookies = _from_environment()
        if cookies is None:
            secret_id = os.environ.get("ESPN_SECRET_ID")
            if not secret_id:
                raise RuntimeError(
                    "set ESPN_SECRET_ID, or ESPN_SWID and ESPN_S2 for local use"
                )
            cookies = _from_secrets_manager(secret_id)
        _cached = cookies
        return _cached


def put_cookies(swid, espn_s2):
    """Replace the stored cookies.

    Never logs either value. Callers are expected to have validated the pair
    against ESPN first -- this does not check, it just writes.
    """
    secret_id = os.environ.get("ESPN_SECRET_ID")
    if not secret_id:
        raise RuntimeError("ESPN_SECRET_ID is not set; nowhere to write")

    import boto3  # imported lazily so tests need no AWS SDK

    client = boto3.client("secretsmanager")
    client.put_secret_value(
        SecretId=secret_id,
        SecretString=json.dumps({"SWID": swid, "espn_s2": espn_s2}),
    )
    reset()


def normalize_swid(value):
    """ESPN's SWID is a GUID in curly braces; people copy it bare."""
    value = (value or "").strip()
    if not value:
        return ""
    value = value[len("SWID="):] if value.startswith("SWID=") else value
    return value if value.startswith("{") else "{" + value.strip("{}") + "}"


def reset():
    """Drop the cached cookies so the next call re-reads them."""
    global _cached
    with _lock:
        _cached = None
