#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# reconcile-out-of-band.sh
# -----------------------------------------------------------------------------
# Finds resources that exist in a customer's Jamf Protect tenant but have NO
# entry in Terraform state, because someone created it in the console and
# invisible to `terraform plan` and to drift detection. Terraform does not know
# they exist, so it cannot report them as changed.
#
# It diffs `terraform query -json` (everything the provider's list resources can
# see in the tenant) against `terraform show -json` (everything Terraform
# manages). Present in the tenant, absent from state = out of band.
#
# Built-in and system resources: the Default plan, the Full Admin and Read Only
# roles, the Default analytic set and action configuration, Jamf Managed Default
# Exceptions: are filtered out upstream by the provider's list resources (see
# exclude_builtins in reconcile.tfquery.hcl), so they never reach this script.
#
# The one exclusion applied here is the bootstrap API client: the credential
# created by hand in every tenant so Terraform can authenticate at all. It is
# intentionally unmanaged and exists everywhere, so without this filter it would
# be a permanent false positive on every customer, every week. It is matched by
# NAME because that is what is constant across tenants: each tenant's client
# has a different id.
#
# Usage:
#   reconcile-out-of-band.sh <query.json> <state.json> <out.json>
#
# Arguments:
#   query.json  `terraform query -json` output (newline-delimited JSON).
#   state.json  `terraform show -json` output.
#   out.json    Where to write the result: a JSON array of
#               { resource_type, id, display_name } objects, or [] when nothing
#               is out of band. Downstream steps consume this.
#
# Environment:
#   RECONCILE_SKIP_API_CLIENT_NAME  Name of the bootstrap API client to exclude.
#                                   Defaults to "terraform-bootstrap". Set it to
#                                   whatever you named yours, or this
#                                   filter does nothing.
#
# Output:
#   Prints the number of out-of-band resources found (last line of stdout).
#   Exits 0 on success. Finding resources is a normal outcome, not an error,
#   or 2 on invalid invocation, a missing dependency, or a missing input.
# -----------------------------------------------------------------------------
set -euo pipefail

QUERY_JSON="${1:?path to 'terraform query -json' output required}"
STATE_JSON="${2:?path to 'terraform show -json' output required}"
OUT_JSON="${3:?path to write the JSON result required}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: required dependency 'jq' not found on PATH" >&2
  exit 2
fi

if [[ ! -f "$QUERY_JSON" ]]; then
  echo "error: query output not found: $QUERY_JSON" >&2
  exit 2
fi
if [[ ! -f "$STATE_JSON" ]]; then
  echo "error: state output not found: $STATE_JSON" >&2
  exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
state_keys="$workdir/state_keys.tsv"
tenant_records="$workdir/tenant_records.tsv"
oob_records="$workdir/oob_records.tsv"

# --- State side --------------------------------------------------------------
# Every jamfprotect_* managed resource, keyed by type + identity. Resources live
# under module.protect, so recurse through child modules rather than reading the
# root module only. Match on the resource identity where present, falling back
# to the `id` attribute. Both hold the same canonical value the list resource
# emits.
jq -r '
  [ (.values.root_module // {}) | recurse(.child_modules[]?) | .resources[]? ]
  | .[]
  | select(.type | startswith("jamfprotect_"))
  | . as $r
  | ( $r.identity.id // $r.values.id // empty ) as $id
  | select($id != "" and $id != null)
  | [ $r.type, ($id | tostring) ] | @tsv
' "$STATE_JSON" 2>/dev/null | sort -u > "$state_keys" || true

# --- Sanity check on the query output ----------------------------------------
# Guard against a silent false negative, which is the dangerous failure mode
# here: reporting "0 out-of-band resources" when in fact the query never ran.
#
# `terraform query -json` frames every list block with list_start/list_complete
# events and emits list_resource_found per resource, so a healthy run ALWAYS
# contains at least the framing events, even against a tenant with nothing out
# of band. No list events at all means either the list blocks did not execute or
# the (experimental) -json event schema changed underneath us. Fail loudly
# rather than emit an empty result that looks like a clean bill of health.
list_events="$(jq -s '
  [ .[]
    | select(type == "object")
    | .type // empty
    | select(. == "list_start" or . == "list_complete" or . == "list_resource_found")
  ] | length
' "$QUERY_JSON" 2>/dev/null || echo 0)"
if [[ "${list_events:-0}" -eq 0 ]]; then
  echo "error: no terraform 'list' events (list_start/list_complete/list_resource_found) in $QUERY_JSON;" >&2
  echo "       the query did not run, or the -json schema changed. Refusing to report an empty" >&2
  echo "       result, which would mask every out-of-band resource." >&2
  exit 2
fi

# --- Tenant side -------------------------------------------------------------
jq -r '
  select(type == "object" and .type == "list_resource_found")
  | .list_resource_found
  | select(.identity.id != null)
  | [ .resource_type, (.identity.id | tostring), (.display_name // "") ] | @tsv
' "$QUERY_JSON" | sort -u > "$tenant_records"

readonly BOOTSTRAP_API_CLIENT_TYPE="jamfprotect_api_client"
readonly BOOTSTRAP_API_CLIENT_NAME="${RECONCILE_SKIP_API_CLIENT_NAME:-terraform-bootstrap}"

# --- The diff ----------------------------------------------------------------
# Out of band = tenant records whose (type, id) is not in state, minus the
# bootstrap client.
#
# Matched on FILENAME rather than the usual NR==FNR idiom for a reason: when
# state contains no in-scope resources, state_keys is empty, and NR==FNR would
# then treat the FIRST LINE of the tenant file as the start of the "seen" set
# and report nothing, a silent failure masking every out-of-band resource.
# FILENAME matching over-reports on empty state instead, which is the safe
# direction to fail in.
awk -F'\t' -v statef="$state_keys" \
    -v skip_type="$BOOTSTRAP_API_CLIENT_TYPE" \
    -v skip_name="$BOOTSTRAP_API_CLIENT_NAME" '
  FILENAME == statef { seen[$1 SUBSEP $2] = 1; next }
  ($1 == skip_type && $3 == skip_name) { next }
  !($1 SUBSEP $2 in seen)
' "$state_keys" "$tenant_records" > "$oob_records"

oob_count="$(wc -l < "$oob_records" | tr -d '[:space:]')"

# Always write the result file, even when empty, so downstream steps can consume
# it without existence checks.
if [[ -s "$oob_records" ]]; then
  jq -R -s -c '
    split("\n")
    | map(select(length > 0))
    | map(split("\t"))
    | map({ resource_type: .[0], id: .[1], display_name: (.[2] // "") })
  ' "$oob_records" > "$OUT_JSON"
else
  printf '[]' > "$OUT_JSON"
fi

echo "$oob_count"
