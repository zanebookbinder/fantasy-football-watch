# watch-my-fantasy-team

A personal watchOS app and Smart Stack widget showing the live score of an ESPN
fantasy matchup — both team totals, win probability, projected points, and every
starter's live points with an ESPN-style stat line.

ESPN's fantasy API is unofficial and needs your account cookies, so an AWS
Lambda holds those cookies and hands the watch a clean, cookie-free payload.
**The cookies never reach the device.**

Built from the design document in [`docs/design-document.md`](docs/design-document.md).

```
watch (app + widget)  ──GET /score + x-api-key──▶  Lambda  ──cookies──▶  ESPN
                      ◀──────compact JSON────────           ◀── raw JSON ──
```

## Layout

| Path | What it is |
| --- | --- |
| `lambda/app/` | The Python proxy: handler, ESPN client, parser, stat lines, cache |
| `lambda/template.yaml` | SAM stack — function, Function URL, secret, IAM, log group |
| `lambda/tests/` | 34 tests, run against a real captured week |
| `lambda/tools/` | Fixture capture and sample-payload generation |
| `scripts/` | Cookie refresh |
| `FantasyWatch/Shared/` | Codable models, networking, config — compiled into both targets |
| `FantasyWatch/WatchApp/` | The full-detail app: header, starter list, polling loop |
| `FantasyWatch/WatchWidget/` | The Smart Stack widget and its timeline provider |
| `docs/sample-payload.json` | The frozen contract, as real data |

## The contract

Everything ESPN-specific happens server-side. The watch decodes this and nothing
else — no stat ids, no cookies, no ESPN hosts.

```json
{
  "state": "ok",
  "week": 2,
  "updated": "2026-09-19T17:40:00Z",
  "leagueSize": 10,
  "me":  { "team": "The Christian Faith", "live": 47.62, "projected": 142.6, "winProb": 0.69,
           "rank": 1, "record": "1-0", "seed": 1,
           "toPlay": 7, "playing": 0, "done": 2, "remaining": 95.0 },
  "opp": { "team": "Team Tïts", "live": -0.1, "projected": 108.6, "winProb": 0.31,
           "rank": 10, "record": "1-0", "seed": 3,
           "toPlay": 8, "playing": 0, "done": 1, "remaining": 108.7 },
  "players": [
    {
      "name": "Josh Allen", "slot": "QB", "position": "QB", "proTeam": "BUF",
      "gameState": "final", "points": 40.82, "projected": 22.7,
      "statLine": "20/31, 248 yd, 3 TD · 14 car, 69 yd, 2 TD",
      "id": 3918298,
      "opponent": "DET", "kickoff": "2026-09-18T00:15:00Z", "clock": null,
      "injury": null, "side": "me",
      "stats": { "cmp": 20, "att": 31, "passYd": 248, "passTd": 3,
                 "car": 14, "rushYd": 69, "rushTd": 2 }
    }
  ]
}
```

`players` carries **both** lineups, each tagged `side`, so the app flips to the
opponent with no second request. `state` is `ok` | `auth_expired` |
`upstream_error` | `no_matchup`.

Notes on the numbers:

- `live` is `totalPointsLive`. `totalPoints` stays `0.0` until ESPN finalizes,
  so reading it would show a zero all afternoon.
- `projected` is `totalProjectedPointsLive` per team and the `statSourceId == 1`
  split per player — it decays toward the live total as games finish.
- `winProb` is ESPN's own `winProbability`, and the two sides sum to 1.
- Points carry two decimals (as ESPN shows them); projections carry one.
- `statLine` is `""` when a player has done nothing. Rather than printing a row
  of zeros, the watch falls back to `opponent` + `kickoff` — "@SF Sun 1pm" tells
  you when to care in a way "yet to play" does not.
- `opponent` is `"@SF"` on the road and `"NE"` at home; `kickoff` is UTC and the
  watch renders it in the wearer's own timezone. `clock` is `"Q3 4:12"` while a
  game is in progress and `null` otherwise.
- `toPlay` / `playing` / `done` count starters, and `remaining` sums the
  projections of those yet to kick off. **A live score is close to meaningless
  without these** — 47.62 to −0.10 looks decisive until you notice the other
  side still has eight starters to play and 108.7 projected points coming.
- `rank` is this week's position by live score across the whole league,
  `leagueSize` teams; `record` is `"1-0"` and `seed` the current playoff seed.
- `stats` carries the same numbers as `statLine` unformatted, and only the
  non-zero ones. The watch diffs two readings of it to say what a player has
  done since you last looked — something a formatted string cannot support.
  `id` is ESPN's player id, which is what those readings are keyed by.

`GET /teams` lists the league for the "my team" picker:

```json
{ "state": "ok",
  "teams": [ { "id": 7, "name": "The Christian Faith", "abbrev": "ZANE",
               "record": "1-0", "seed": 1 } ] }
```

`teamId` on `/score` selects whose matchup to return, defaulting to the
`TEAM_ID` env var. Each team caches independently, so switching back and forth
does not evict the team you came from.

Regenerate `docs/sample-payload.json` with `make sample` — it also refreshes the
copy bundled into both watch targets, so the two halves never drift.

## Backend setup

```bash
# 1. A client key for the watch to present.
openssl rand -hex 24

# 2. Deploy. Pass the key above as ClientApiKey.
cd lambda && sam build && sam deploy --guided
```

The stack creates the secret with a throwaway value, so put the real cookies in
separately — they never touch the template or CloudFormation's history:

```bash
aws secretsmanager put-secret-value \
  --secret-id watch-my-fantasy-team/espn-cookies \
  --secret-string '{"SWID":"{...}","espn_s2":"..."}'
```

Or just run `make refresh-cookies`, which does the same thing with a hidden
prompt and checks the cookies against ESPN first — see below.

Then check it:

```bash
curl -H "x-api-key: $CLIENT_API_KEY" "$SCORE_URL/score"
```

`sam deploy` prints `ScoreUrl` and `SecretId` as stack outputs.

## Refreshing the cookies

Two ways, same outcome. Both validate the cookie against ESPN before writing,
so a bad paste always leaves a working secret alone.

### From the Mac

```bash
make refresh-cookies
```

Reuses the stored `SWID`, takes the new `espn_s2` on a hidden prompt, writes it
via the AWS CLI, then waits for the endpoint to serve `ok` again.

### From anything that can make an HTTP request

`POST /cookies` rotates the session with no AWS credentials involved — useful
from a phone, a Shortcut, or any machine without the AWS CLI:

```bash
source .secrets.env    # gitignored; holds SCORE_URL and both keys

curl -X POST "$SCORE_URL/cookies" \
  -H "x-admin-key: $ADMIN_API_KEY" \
  -H 'content-type: application/json' \
  -d '{"espn_s2":"PASTE_IT_HERE"}'
```

`{"state":"ok"}` means saved and live. `{"state":"rejected"}` means ESPN did not
accept the pair and **nothing was written**. `SWID` is optional — omit it and the
stored one is reused; send it bare or braced, either works.

**The write key is deliberately not the read key.** `CLIENT_API_KEY` is compiled
into the watch app, on a device you could lose; it gets a `403` on this endpoint.
Only `ADMIN_API_KEY` can rotate the session.

### When it expires

`espn_s2` expires. When it does, ESPN returns 401, the Lambda answers
`auth_expired`, and the watch shows **Reconnect** — that's the signal, and it's
the only warning you get. Then run either of the above.

Recovery takes up to the cache TTL and needs no restart: on a 401 the Lambda
drops its in-memory cookies, so the next request past the ~20s payload TTL
re-reads the secret by itself. A write through `POST /cookies` clears that
container's cache immediately.

**How often?** Nobody can say precisely. `SWID` is your account's GUID and
effectively never changes, so this is really only ever the one value. `espn_s2`
is issued with a long nominal expiry (check the `Expires` column in DevTools for
yours) but is invalidated early by logging out anywhere, changing your password,
or Disney rotating sessions. Reported lifetimes run from a few weeks to a whole
season. Since the cost of being surprised is one `make refresh-cookies`, this is
built to be cheap rather than predictable.

**Why the watch can't do this itself.** The cookies live in a browser, on a
different device. watchOS has no browser, no access to Safari's cookie store,
and no `ASWebAuthenticationSession` — there is nothing on the watch for it to
read. Automating it further means either an iOS companion app that harvests
cookies from a `WKWebView` after you log in, or scripting the Disney OneID login
with your account password. The latter is deliberately not built here: a
password is a strictly more powerful secret than the cookie it would replace, it
breaks under 2FA and CAPTCHA, and it would be run from an AWS IP that Disney is
far more likely to challenge than your home connection.

### Configuration

| Env var | Default | Purpose |
| --- | --- | --- |
| `ESPN_SECRET_ID` | — | Secrets Manager id holding `SWID` and `espn_s2` |
| `CLIENT_API_KEY` | — | Key the watch sends as `x-api-key` for reads; **unset means every request is refused** |
| `ADMIN_API_KEY` | — | Key for `POST /cookies`, sent as `x-admin-key`; must differ from `CLIENT_API_KEY` |
| `LEAGUE_ID` | `1896305934` | |
| `TEAM_ID` | `7` | |
| `SEASON` | `2026` | |
| `CACHE_TTL_SECONDS` | `20` | The live-ness knob — see below |

For local runs, `ESPN_SWID` and `ESPN_S2` bypass Secrets Manager, and
`REQUIRE_API_KEY=false` bypasses the key check. Neither belongs in a deployed
stack.

### Caching

The watch polls every ~25s; ESPN sees at most about three calls a minute,
because a module-level cache absorbs the rest. `CACHE_TTL_SECONDS` is the knob:
raise it to touch ESPN less, lower it for fresher numbers. Fantasy scoring
updates on roughly this cadence anyway, so 20s loses nothing.

On an ESPN hiccup the Lambda serves the last successful payload rather than an
error — `updated` keeps the staleness honest.

## Watch app setup

1. `cp FantasyWatch/Config/Secrets.example.xcconfig FantasyWatch/Config/Secrets.xcconfig`
2. Fill in `LAMBDA_BASE_URL` (the `ScoreUrl` output, no trailing slash) and
   `CLIENT_API_KEY`. Write `//` as `$(SLASH)$(SLASH)` — an xcconfig reads a
   literal `//` as the start of a comment.
3. Open `FantasyWatch/FantasyWatch.xcodeproj` and run the `FantasyWatch` scheme.

`Secrets.xcconfig` is gitignored, and `Base.xcconfig` includes it optionally, so
a fresh clone still builds (it just shows "not configured").

Set your own `DEVELOPMENT_TEAM` and bundle identifiers before running on a
physical watch. The bundle ids default to
`com.zanebookbinder.FantasyWatch.watchkitapp` and `…watchkitapp.widget`; the
widget's id must stay a child of the app's.

### Picking your team

On first launch the app lists the league and asks which team is yours; the
choice is remembered and every week's matchup follows it. "My team" at the
bottom of the scroll changes it, behind a confirmation — switching throws away
the cached matchup and every change baseline.

The choice lives in an App Group so the widget follows the same team. **That
sharing is unverified**: `simctl install` does not create third-party App Group
containers, so in the simulator the suite quietly falls back to per-process
storage and the widget keeps using the Lambda's default team. It should work on
a device once the App Group capability is registered for the App ID, which
automatic signing does on the first device build.

### What changed since you last looked

Every player's points and stats are remembered between visits. A player whose
score has moved gets a blue dot; opening their row shows "+7.7 points since
last view" and the stats behind it ("1 rec, 7 yd, 1 TD"). Opening the row
retires the dot, and it returns only if the score moves again, up or down.

The baseline advances for players with nothing to show and for players whose
row you opened — never wholesale on launch, which would clear a dot you never
actually saw. `make check-watch` pins those rules down.

### Refresh behaviour

| Surface | How it refreshes | Realistic cadence |
| --- | --- | --- |
| App, foreground | Its own polling loop | Every 25s — near-live |
| App, backgrounded | Stops | Not live |
| Widget | WidgetKit timeline, system-scheduled | Minutes apart, best-effort |

The polling loop is tied to `scenePhase` and is cancelled the moment the app
backgrounds. The widget asks for a 15-minute refresh while a starter is mid-game
and an hour otherwise, and raises its relevance during games so the Smart Stack
floats it up — but watchOS decides, within a limited daily budget. **Open the app
for live; treat the widget as a frequently-updated glance, not a ticker.**

## Developing

```bash
make test             # Lambda test suite
make typecheck        # both watch targets against the watchOS SDK
make check-watch      # watch-side change-tracking rules
make sample           # regenerate the contract sample
make refresh-cookies  # push fresh ESPN cookies to Secrets Manager
make fixture RAW=~/Downloads/fantasy-data.json   # rebuild the test fixture
```

`lambda/tests/fixtures/league-week2.json` is a 59 KB trim of a real week-2
response — real data, small enough to commit. The raw 1.5 MB response is
gitignored; don't commit one.

## Two ESPN gotchas worth not relearning

**The two hosts want opposite User-Agents.** `lm-api-reads` (the private fantasy
read) 401s anything that is not browser-shaped. `site.api` (the public NFL
scoreboard) does the reverse: it 403s a Chrome UA *even with a full set of
Accept / Referer / Sec-Fetch-\* headers*, and serves plain clients happily.
Sending the browser UA to both looks tidy and silently breaks the scoreboard —
which is exactly what happened here, and the `gameState` fallback is plausible
enough that it went unnoticed in production for a while. There is now a test
pinning each host to its own UA, and the scoreboard failure logs at error level.

**Kickoff times arrive without seconds.** ESPN sends `2026-09-25T00:15Z`, which
strict ISO 8601 parsers — Swift's `.iso8601` among them — reject outright. The
Lambda normalizes them before they reach the contract.

## Known limitations

- **K and D/ST stat ids are unverified.** Every offensive skill id in
  `lambda/app/constants.py` was read out of this league's own response. The
  kicking and defense ids come from the community `espn-api` map and no kicker
  or defense had scored in the sampled week. Confirm them against real output
  before trusting those two lines; they are constants in one file.
- **A player on a bye reads `pre`.** The contract is `pre | live | final`, so a
  team with no game this week falls into `pre`. The Swift enum decodes unknown
  values to `pre`, so adding a `bye` state later is a Lambda-only change.
- **The widget and app keep separate offline caches.** They are separate
  processes and share no App Group, which keeps entitlements out of the picture.
  A shared container would be the v2 fix.
- **Building needs the watchOS simulator runtime.** Xcode → Settings →
  Components. Without it `actool` fails before the Swift even compiles;
  `make typecheck` works regardless.
- **The AWS tools must be the arm64 builds.** The x86_64 SAM and AWS CLIs stop
  running the moment Rosetta is unavailable (`bad CPU type in executable`),
  which takes out `make deploy` and `make refresh-cookies` together. Install
  them from the Apple Silicon Homebrew (`brew install awscli aws-sam-cli`) and
  make sure `/opt/homebrew/bin` precedes `/usr/local/bin` on `PATH`, or the dead
  Intel copies shadow the working ones. `POST /cookies` needs only curl, so
  cookie rotation survives a broken toolchain either way.
- **ESPN can break without notice.** It has changed hosts and API versions
  before. All of that lives in the Lambda, so a break is a `sam deploy`, not an
  app rebuild.

## Not built (v2)

APNs push plus an EventBridge schedule for a fresher widget; multi-league
support; anything that writes back to ESPN.

This is personal-use only — the ESPN API is unofficial and redistribution is
against its terms.
