#!/usr/bin/env bash
# shellcheck disable=SC2016  # Single-quoted printf templates (literal Markdown
# backticks) and jq programs ($audit/$a/$r are jq variables, not shell) are
# intentional.
# -----------------------------------------------------------------------------
# build-out-of-band-report.sh
# -----------------------------------------------------------------------------
# Renders the Markdown body for an out-of-band resource GitHub issue.
#
# Takes the machine-readable list from reconcile-out-of-band.sh and, optionally,
# a Jamf Protect audit-log export; joins them to attribute each resource to
# whoever created it; writes Markdown to stdout.
#
# Attribution is best-effort. A resource created before the lookback horizon, or
# of a type the audit log does not cover, shows a dash. A missing or empty audit
# file simply omits attribution for every row — the detection result still
# stands, which is the part that matters.
#
# Usage:
#   build-out-of-band-report.sh <oob.json> <audit.json> <customer> <run_url>
#
# Arguments:
#   oob.json    JSON array from reconcile-out-of-band.sh.
#   audit.json  JSON array from `jamf-cli protect audit-logs list -o json`.
#               Pass /dev/null or a non-existent path to skip attribution.
#   customer    Customer directory name, for the heading.
#   run_url     Workflow run URL, for traceability.
#
# Environment:
#   REPORT_MENTION  Optional @mention to add to the issue body, e.g.
#                   "@your-org/your-team" or "@username". Unset means no mention.
# -----------------------------------------------------------------------------
set -euo pipefail

OOB_JSON="${1:?path to oob.json required}"
AUDIT_JSON="${2:?path to audit.json required (use /dev/null to skip attribution)}"
CUSTOMER="${3:?customer name required}"
RUN_URL="${4:?run url required}"

REPORT_MENTION="${REPORT_MENTION:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: required dependency 'jq' not found on PATH" >&2
  exit 2
fi

# Normalise the audit input to an array — empty when absent, unreadable or blank
# — so the join below never fails just because attribution was unavailable.
audit_norm="$(mktemp)"
trap 'rm -f "$audit_norm"' EXIT
if [[ -s "$AUDIT_JSON" ]] && jq -e 'type == "array"' "$AUDIT_JSON" >/dev/null 2>&1; then
  cp "$AUDIT_JSON" "$audit_norm"
else
  printf '[]' > "$audit_norm"
fi

# See audit-op-map.json. Audit entries key only on resourceId, which collides
# across types — a plan, a role and an action config can all be id "1" — so
# attribution matches resourceId AND the op noun for the type. A type absent
# from the map is left unattributed rather than matched on resourceId alone.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPMAP="$SCRIPT_DIR/audit-op-map.json"

# Join each out-of-band resource to its audit events: earliest create event
# (who put it there) and most recent event of any kind (whether it is still
# being changed).
enriched="$(jq -c --slurpfile audit "$audit_norm" --slurpfile opmap "$OPMAP" '
  ($audit[0] // []) as $a
  | ($opmap[0] // {}) as $m
  | map(
      . as $r
      | ($m[$r.resource_type]) as $noun
      | (if $noun == null then []
         else ($a | map(select(
           .resourceId == $r.id
           and (.op | test("^(create|update|delete)" + $noun + "$"))
         ))) end) as $events
      | ($events | map(select(.op | test("^create"))) | sort_by(.date) | first) as $created
      | ($events | sort_by(.date) | last) as $last
      | $r + {
          created: (if $created then { date: $created.date, user: $created.user, ips: $created.ips } else null end),
          last_op: (if $last then { op: $last.op, date: $last.date } else null end)
        }
    )
' "$OOB_JSON")"

count="$(printf '%s' "$enriched" | jq 'length')"

printf '## Out-of-band resources detected for `%s`\n\n' "$CUSTOMER"
printf '%s\n\n' "The following resources exist in the Jamf Protect tenant but are **not** managed by Terraform. They have no entry in state, so they are invisible to \`terraform plan\` and to drift detection."
printf ':mag: **%s** out-of-band resource(s) found.\n\n' "$count"
printf '%s\n\n' "Each one needs a decision: **import** it into Terraform if it should exist, or **delete** it from the tenant if it should not. Record the decision on this issue — an unanswered finding here is the same problem as the drift it was written to catch."

if [ -n "$REPORT_MENTION" ]; then
  printf 'cc %s\n\n' "$REPORT_MENTION"
fi

printf '| Resource type | Name | ID | Created by | Created (UTC) | Source IP | Last activity |\n'
printf '| --- | --- | --- | --- | --- | --- | --- |\n'
# Escape pipe characters in free-text fields so a resource name cannot break the
# table layout.
printf '%s' "$enriched" | jq -r '
  def cell: if . == null or . == "" then "—" else (. | tostring | gsub("\\|"; "\\|")) end;
  .[]
  | "| `\(.resource_type)` "
    + "| \(.display_name | cell) "
    + "| `\(.id)` "
    + "| \(.created.user | cell) "
    + "| \(.created.date | cell) "
    + "| \(.created.ips | cell) "
    + "| \(if .last_op then "\(.last_op.op) (\(.last_op.date))" else "—" end) |"
'

printf '\n> Attribution comes from the Jamf Protect audit log, paged back to the configured lookback horizon. A dash means no matching audit event was found within that horizon — the resource predates it, or its type is not captured in the audit log.\n'
printf '\n**Workflow run:** %s\n' "$RUN_URL"
