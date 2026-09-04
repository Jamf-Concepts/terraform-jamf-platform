#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# fetch-audit-logs.sh
# -----------------------------------------------------------------------------
# Fetches Jamf Protect audit-log entries so out-of-band resources can be
# attributed to the account that created them, and writes them as a JSON array.
#
# The audit-log API caps each query at a 7-day window, and the SDK clamps
# anything larger to the last 7 days. Older history IS retained and queryable;
# you have to page `--end` backwards in 7-day chunks. This script does
# that, but lazily:
#
#   1. Fetch the most recent 7-day window.
#   2. If every out-of-band resource already has a creation event, stop. Most
#      runs end here, having made a single API call.
#   3. Otherwise page older windows until either everything is attributed or the
#      lookback horizon is reached.
#
# So steady-state cost is one window, while a first run against a long-standing
# tenant can still attribute resources created weeks ago.
#
# Usage:
#   fetch-audit-logs.sh <oob.json> <out-audit.json> [horizon_days]
#
# Arguments:
#   oob.json        JSON array from reconcile-out-of-band.sh; drives the early
#                   stop.
#   out-audit.json  Where to write the merged, de-duplicated audit array.
#   horizon_days    Maximum days to look back (default 30). A value <= 7 fetches
#                   only the most recent window. Raise it for a one-off backfill.
#
# Requires: jamf-cli (authenticated via JAMFPROTECT_* environment variables), jq.
#
# Never fails the caller. Attribution is a nice-to-have on top of detection, so
# a fetch error writes whatever it gathered, an empty array at worst, and the
# report shows dashes instead of names.
# -----------------------------------------------------------------------------
set -uo pipefail

OOB_JSON="${1:?path to oob.json required}"
OUT_AUDIT="${2:?path to write audit json required}"
HORIZON_DAYS="${3:-30}"

# Fixed by the API, not a tuning knob.
WINDOW_DAYS=7

if ! command -v jq >/dev/null 2>&1; then
  echo "error: required dependency 'jq' not found on PATH" >&2
  exit 2
fi

readonly len_filter='length'

# Portable "N days ago" in RFC3339 UTC: GNU date on CI runners, BSD date locally.
days_ago() {
  local days="$1"
  date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ
  return
}
now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
  return
}

acc="$(mktemp)"
trap 'rm -f "$acc"' EXIT
printf '[]' > "$acc"

# Resource type -> audit-log op noun. See audit-op-map.json for why this
# indirection exists: resourceId is unique only within a type, so a creation
# event has to match both.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPMAP="$SCRIPT_DIR/audit-op-map.json"

# How many out-of-band resources still have no creation event in the
# accumulator. Drives the deep-lookback early stop.
#
# Types absent from the op map have no known noun and are unattributable:
# matching on resourceId alone would falsely pin them to a same-id event of a
# different type. They are excluded here so they neither get mis-attributed nor
# keep the loop paging backwards forever chasing an event it can never match.
unattributed_count() {
  jq -s --slurpfile oob "$OOB_JSON" --slurpfile opmap "$OPMAP" '
    (.[0]) as $audit
    | ($opmap[0] // {}) as $m
    | [ $oob[0][]
        | . as $r
        | ($m[$r.resource_type]) as $noun
        | select($noun != null)
        | ($audit | map(select(
            .resourceId == $r.id
            and (.op | test("^create" + $noun + "$"))
          )) | length) as $creates
        | select($creates == 0)
      ] | length
  ' "$acc"
  return
}

fetch_window() {
  local start="$1" end="$2"
  local out
  echo "  fetching audit window [$start, $end]" >&2
  if out="$(jamf-cli protect audit-logs list --start "$start" --end "$end" \
      -o json --no-input --no-version-check 2>/dev/null)" \
      && printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1; then
    jq -s '(.[0] + .[1]) | unique' "$acc" <(printf '%s' "$out") > "$acc.tmp" \
      && mv "$acc.tmp" "$acc"
  else
    echo "  window fetch failed; continuing" >&2
  fi
  return
}

# Window 0: the most recent 7 days. Often the only call made.
fetch_window "$(days_ago "$WINDOW_DAYS")" "$(now_iso)"

# Deep lookback, only while resources remain unattributed and within horizon.
if [[ "$HORIZON_DAYS" -gt "$WINDOW_DAYS" ]]; then
  oob_total="$(jq "$len_filter" "$OOB_JSON")"
  if [[ "$oob_total" -gt 0 ]]; then
    j=1
    while [[ "$(unattributed_count)" -gt 0 ]]; do
      start_off=$(( WINDOW_DAYS * (j + 1) ))
      end_off=$(( WINDOW_DAYS * j ))
      if [[ "$end_off" -ge "$HORIZON_DAYS" ]]; then
        echo "  reached lookback horizon (${HORIZON_DAYS}d); stopping" >&2
        break
      fi
      before="$(jq "$len_filter" "$acc")"
      fetch_window "$(days_ago "$start_off")" "$(days_ago "$end_off")"
      after="$(jq "$len_filter" "$acc")"
      # No new entries means there is no more history to page through, so stop
      # rather than burn calls walking back to the horizon regardless.
      if [[ "$after" -eq "$before" ]]; then
        echo "  no further audit history in this window; stopping" >&2
        break
      fi
      j=$(( j + 1 ))
    done
  fi
fi

cp "$acc" "$OUT_AUDIT"
echo "collected $(jq "$len_filter" "$OUT_AUDIT") audit entries; $(unattributed_count) resource(s) still unattributed" >&2
