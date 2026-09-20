"""Short-TTL in-memory cache plus a last-good fallback.

This is what lets the watch poll every 20s without ESPN ever seeing more than
about three calls a minute (design doc, "Caching is what makes 'as often as it
can' safe").
"""

import time


class KeyedCache:
    """One PayloadCache per key, so each team caches independently.

    A watch that switches teams should not evict the cache of the team it just
    left, and two teams' payloads must never be served for one another.
    """

    def __init__(self, ttl_seconds=20.0):
        self.ttl = ttl_seconds
        self._caches = {}

    def _for(self, key):
        if key not in self._caches:
            self._caches[key] = PayloadCache(ttl_seconds=self.ttl)
        return self._caches[key]

    def get(self, key):
        return self._for(key).get()

    def put(self, key, payload):
        self._for(key).put(payload)

    def last_good(self, key):
        return self._for(key).last_good

    def clear(self, key=None):
        if key is None:
            for cache in self._caches.values():
                cache.clear()
        else:
            self._for(key).clear()


class PayloadCache:
    def __init__(self, ttl_seconds=20.0):
        self.ttl = ttl_seconds
        self._value = None
        self._stored_at = 0.0
        self._last_good = None

    def get(self):
        """Return the cached payload if it is still fresh, else None."""
        if self._value is None:
            return None
        if time.monotonic() - self._stored_at > self.ttl:
            return None
        return self._value

    def put(self, payload):
        self._value = payload
        self._stored_at = time.monotonic()
        if payload.get("state") == "ok":
            self._last_good = payload

    @property
    def last_good(self):
        """The most recent successful payload, however stale.

        Served when ESPN hiccups so a transient failure shows a slightly old
        score rather than an error. Its own ``updated`` field keeps the
        staleness honest.
        """
        return self._last_good

    def clear(self):
        self._value = None
        self._stored_at = 0.0
