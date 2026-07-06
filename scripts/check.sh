#!/usr/bin/env bash
#
# check.sh — check every site in sites.json for liveness AND correctness.
#
# A check fails when any of these is true:
#   - HTTP status >= 400 (>= 500 for api:true endpoints)
#   - redirects land on a different host (unless listed in allow_hosts)
#     -> catches "returns 200 but serves the WRONG product" failures
#   - body does not contain the expected brand substring (case-insensitive)
#
# Output: one line per site (OK/FAIL + reason). Exit 1 if any site failed.
# Failures are also written to failures.txt (one "host<TAB>reason" per line)
# for the workflow's issue-management step.
#
set -uo pipefail

CONFIG="$(dirname "$0")/../sites.json"
FAILURES_FILE="${FAILURES_FILE:-failures.txt}"
: > "$FAILURES_FILE"
FAIL_COUNT=0

host_of() { echo "$1" | sed -E 's#^https?://##; s#/.*$##; s#^www\.##'; }

count=$(jq '.sites | length' "$CONFIG")
for i in $(seq 0 $((count - 1))); do
  url=$(jq -r ".sites[$i].url" "$CONFIG")
  body_expect=$(jq -r ".sites[$i].body // empty" "$CONFIG")
  is_api=$(jq -r ".sites[$i].api // false" "$CONFIG")
  allow_hosts=$(jq -r "(.sites[$i].allow_hosts // []) | join(\" \")" "$CONFIG")
  expected_host=$(host_of "$url")

  body_file=$(mktemp)
  # 2 retries, 20s ceiling per attempt; -L follows up to 5 redirects
  result=$(curl -sS -L --max-redirs 5 --retry 2 --retry-delay 5 -m 20 \
    -o "$body_file" -w "%{http_code} %{url_effective}" "$url" 2>/dev/null) || result="000 $url"
  status="${result%% *}"
  final_url="${result#* }"
  final_host=$(host_of "$final_url")

  reasons=""
  # 1. status
  limit=400; [ "$is_api" = "true" ] && limit=500
  if [ "$status" = "000" ]; then
    reasons="unreachable (connection failed/timeout)"
  elif [ "$status" -ge "$limit" ]; then
    reasons="HTTP $status"
  fi
  # 2. final host must be the site's own host (or explicitly allowed)
  if [ "$final_host" != "$expected_host" ]; then
    allowed=no
    for h in $allow_hosts; do [ "$final_host" = "$(echo "$h" | sed 's#^www\.##')" ] && allowed=yes; done
    if [ "$allowed" = "no" ]; then
      reasons="${reasons:+$reasons; }redirects to WRONG HOST: $final_host"
    fi
  fi
  # 3. content sanity
  if [ -n "$body_expect" ] && [ "$status" != "000" ]; then
    if ! grep -qi "$body_expect" "$body_file"; then
      reasons="${reasons:+$reasons; }body missing expected text \"$body_expect\""
    fi
  fi
  rm -f "$body_file"

  if [ -n "$reasons" ]; then
    echo "FAIL  $expected_host — $reasons (status $status, final: $final_host)"
    printf '%s\t%s\n' "$expected_host" "$reasons (status $status, final host: $final_host)" >> "$FAILURES_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "OK    $expected_host ($status)"
  fi
done

echo ""
echo "$FAIL_COUNT of $count checks failing."
[ "$FAIL_COUNT" -eq 0 ]
