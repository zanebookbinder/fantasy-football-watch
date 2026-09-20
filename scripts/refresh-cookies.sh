#!/usr/bin/env bash
#
# Refresh the ESPN cookies in Secrets Manager.
#
# Validates the new cookie against ESPN *before* saving, so a mistyped paste
# can't leave the stack worse off than it was, then waits for the live endpoint
# to recover so you know it worked without opening the watch.
#
#     make refresh-cookies
#
# The cookies are read with a hidden prompt and never appear in your shell
# history, in an argument list, or in this repo.

set -euo pipefail

STACK_NAME="${STACK_NAME:-watch-my-fantasy-team}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
LEAGUE_ID="${LEAGUE_ID:-1896305934}"
SEASON="${SEASON:-2026}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCCONFIG="$REPO_ROOT/FantasyFootballWatch/Config/Secrets.xcconfig"

UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'

die() { printf '\n\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
note() { printf '\033[2m%s\033[0m\n' "$1"; }
ok() { printf '\033[32m✓\033[0m %s\n' "$1"; }

command -v aws >/dev/null || die "the AWS CLI is not installed"
aws sts get-caller-identity >/dev/null 2>&1 || die "AWS credentials are not configured"

# --- Locate the stack's secret --------------------------------------------
note "Looking up the stack…"
SECRET_ID="$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='SecretId'].OutputValue" \
  --output text 2>/dev/null || true)"
[ -n "$SECRET_ID" ] && [ "$SECRET_ID" != "None" ] \
  || die "couldn't find stack '$STACK_NAME' in $REGION. Deploy it first: make deploy"

SCORE_URL="$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='ScoreUrl'].OutputValue" \
  --output text 2>/dev/null || true)"
SCORE_URL="${SCORE_URL%/}"

# SWID is your account's GUID and effectively never changes, so reuse the
# stored one unless it is still the placeholder or you pass --swid.
CURRENT_SWID="$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" --region "$REGION" \
  --query SecretString --output text 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("SWID",""))' 2>/dev/null || true)"

WANT_SWID=false
[ "${1:-}" = "--swid" ] && WANT_SWID=true
case "$CURRENT_SWID" in
  ""|"replace-me") WANT_SWID=true ;;
esac

cat <<'EOF'

Grab these from a browser logged in to ESPN:
  DevTools → Application → Cookies → https://www.espn.com

EOF

# --- Read the cookies ------------------------------------------------------
if $WANT_SWID; then
  printf 'SWID (with the curly braces): '
  read -r SWID
  SWID="$(printf '%s' "$SWID" | tr -d '[:space:]')"
  SWID="${SWID#SWID=}"
  # Auto-wrap: the value is a GUID in braces and people often copy it bare.
  case "$SWID" in
    "{"*"}") ;;
    "") die "SWID cannot be empty" ;;
    *) SWID="{$SWID}"; note "  (wrapped in braces for you)" ;;
  esac
else
  SWID="$CURRENT_SWID"
  note "Reusing the stored SWID (pass --swid to change it)."
fi

printf 'espn_s2 (hidden, long and URL-encoded): '
read -rs ESPN_S2
printf '\n'
ESPN_S2="$(printf '%s' "$ESPN_S2" | tr -d '[:space:]')"
ESPN_S2="${ESPN_S2#espn_s2=}"
[ -n "$ESPN_S2" ] || die "espn_s2 cannot be empty"

# --- Validate against ESPN before saving anything --------------------------
printf '\n'
note "Checking the cookies against ESPN…"
URL="https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/$SEASON/segments/0/leagues/$LEAGUE_ID?view=mMatchupScore"
CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
  -H "Cookie: SWID=$SWID; espn_s2=$ESPN_S2" \
  -H "User-Agent: $UA" \
  "$URL" || echo 000)"

case "$CODE" in
  200) ok "ESPN accepted them." ;;
  401|403) die "ESPN rejected these cookies ($CODE). Nothing was saved — re-copy them and try again." ;;
  000) die "couldn't reach ESPN. Check your connection; nothing was saved." ;;
  *)   die "ESPN returned $CODE. Nothing was saved." ;;
esac

# --- Save ------------------------------------------------------------------
# Built with python so any character in the cookie is escaped correctly, and
# passed via stdin so the secret never appears in an argument list.
SECRET_JSON="$(SWID="$SWID" ESPN_S2="$ESPN_S2" python3 -c \
  'import json,os; print(json.dumps({"SWID":os.environ["SWID"],"espn_s2":os.environ["ESPN_S2"]}))')"

aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ID" --region "$REGION" \
  --secret-string "$SECRET_JSON" \
  --query VersionId --output text >/dev/null
ok "Saved to Secrets Manager."
unset SECRET_JSON ESPN_S2

# --- Wait for the live endpoint to recover ---------------------------------
# No cache busting needed: on a 401 the Lambda drops its cached cookies, and the
# ~20s payload TTL means the next miss re-reads the secret by itself.
API_KEY=""
if [ -f "$XCCONFIG" ]; then
  API_KEY="$(awk -F'=' '/^[[:space:]]*CLIENT_API_KEY/ {gsub(/[[:space:]]/,"",$2); print $2}' "$XCCONFIG")"
fi

if [ -z "$API_KEY" ] || [ -z "$SCORE_URL" ]; then
  note "Skipping the live check (no client key or endpoint found locally)."
  printf '\nDone. The watch should recover within ~20s.\n'
  exit 0
fi

printf '\n'
note "Waiting for the endpoint to pick it up (up to 60s)…"
for _ in $(seq 1 12); do
  STATE="$(curl -s --max-time 10 -H "x-api-key: $API_KEY" "$SCORE_URL/score" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("state","?"))' 2>/dev/null || echo '?')"
  case "$STATE" in
    ok)
      ok "Endpoint is serving live data again."
      curl -s --max-time 10 -H "x-api-key: $API_KEY" "$SCORE_URL/score" | python3 -c '
import json, sys
p = json.load(sys.stdin)
me, opp = p["me"], p["opp"]
print()
print(f"  Week {p[\"week\"]}")
print(f"  {me[\"team\"]:<24} {me[\"live\"]:>7.2f}   win {me[\"winProb\"]:.0%}")
print(f"  {opp[\"team\"]:<24} {opp[\"live\"]:>7.2f}   win {opp[\"winProb\"]:.0%}")
'
      exit 0
      ;;
    auth_expired) sleep 5 ;;
    *) note "  endpoint says '$STATE', retrying…"; sleep 5 ;;
  esac
done

printf '\n'
note "The secret is saved, but the endpoint hasn't flipped yet."
note "That's usually just a warm container finishing its cache window — try again in a minute."
