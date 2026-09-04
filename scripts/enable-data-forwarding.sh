#!/bin/bash
# -----------------------------------------------------------------------------
# Enable SIEM Data Forwarding
# -----------------------------------------------------------------------------
# Adds Microsoft Sentinel forwarding to an existing customer: prompts for the
# Azure values, stores the secret in the customer's GitHub Environment, writes
# the non-secret values into their tfvars, and opens a pull request.
#
# This is the pattern for adding anything to the menu. The capability already
# exists in the shared module; enabling it for a customer is a values change,
# reviewed like any other. Nobody logs into a console.
#
# Usage: ./scripts/enable-data-forwarding.sh <customer-name> --sentinel
#
# Prerequisites:
#   - gh (GitHub CLI), authenticated
#   - The customer is already onboarded (directory and Environment exist)
#   - An Azure App Registration, Data Collection Endpoint and Data Collection
#     Rules already configured in the customer's Azure tenant. This script does
#     not create any Azure resources. It only wires Jamf Protect to them.
#
# Adding another destination: the module's data_forwarding.tf already carries a
# disabled amazon_s3 block. Add an `--s3` flag here, a matching variable, and
# flip that block's `enabled`.
# -----------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

CUSTOMER=""
DESTINATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sentinel)
      DESTINATION="sentinel"
      shift
      ;;
    -*)
      echo "Error: unknown flag: $1"
      echo "Usage: $0 <customer-name> --sentinel"
      exit 1
      ;;
    *)
      if [ -z "$CUSTOMER" ]; then
        CUSTOMER="$1"
      else
        echo "Error: unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$CUSTOMER" ]; then
  echo "Error: customer-name is required."
  echo "Usage: $0 <customer-name> --sentinel"
  exit 1
fi

if [ -z "$DESTINATION" ]; then
  echo "Error: a destination flag is required."
  echo "Available destinations: --sentinel"
  exit 1
fi

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
CUSTOMER_DIR="customers/${CUSTOMER}"

# Optional: a GitHub team or user to request review from, e.g. "your-org/your-team".
REVIEWERS="${REVIEWERS:-}"

if [ ! -d "${CUSTOMER_DIR}" ]; then
  echo "Error: customer directory '${CUSTOMER_DIR}' does not exist."
  echo "       Has this customer been onboarded?"
  exit 1
fi

echo "==> Verifying GitHub Environment exists..."
if ! gh api "repos/${REPO}/environments/${CUSTOMER}" >/dev/null 2>&1; then
  echo "Error: GitHub Environment '${CUSTOMER}' does not exist."
  echo "       Run onboard-customer.sh first."
  exit 1
fi

if [ "$DESTINATION" = "sentinel" ]; then
  echo "==> Configuring Microsoft Sentinel data forwarding for: ${CUSTOMER}"
  echo

  read -r -p "  → Azure Tenant (Directory) ID: " DIRECTORY_ID
  read -r -p "  → App Registration (Application) ID: " APPLICATION_ID
  read -r -p "  → Data Collection Endpoint URL: " DATA_COLLECTION_ENDPOINT
  echo
  echo "  --- Alerts ---"
  read -r -p "  → Alerts Data Collection Rule Immutable ID: " ALERTS_RULE_ID
  read -r -p "  → Alerts Stream Name: " ALERTS_STREAM_NAME
  echo
  echo "  --- Telemetry ---"
  read -r -p "  → Telemetry Data Collection Rule Immutable ID: " TELEMETRY_RULE_ID
  read -r -p "  → Telemetry Stream Name: " TELEMETRY_STREAM_NAME
  echo
  read -r -s -p "  → Application Secret (hidden): " APP_SECRET
  echo

  # Validate before writing anything. A half-populated forwarding block fails
  # at apply time, by which point the branch and PR already exist.
  for var in DIRECTORY_ID APPLICATION_ID DATA_COLLECTION_ENDPOINT \
             ALERTS_RULE_ID ALERTS_STREAM_NAME \
             TELEMETRY_RULE_ID TELEMETRY_STREAM_NAME APP_SECRET; do
    if [ -z "${!var}" ]; then
      echo "Error: all fields are required. '${var}' is empty."
      exit 1
    fi
  done

  # --- Store the secret ------------------------------------------------------
  # The only value that does not go into the tfvars file. It is write-only from
  # Terraform's point of view: sent to the API, never read back into state.
  echo "==> Storing SENTINEL_APP_SECRET in the ${CUSTOMER} GitHub Environment..."
  echo "${APP_SECRET}" | gh secret set SENTINEL_APP_SECRET --env "${CUSTOMER}" --repo "${REPO}"

  # --- Update customer.auto.tfvars -------------------------------------------
  echo "==> Writing Sentinel configuration into customer.auto.tfvars..."
  TFVARS_FILE="${CUSTOMER_DIR}/customer.auto.tfvars"

  # Strip the commented template block, then append the populated one. Portable
  # in-place edit: BSD sed needs an argument to -i, GNU sed needs none, so use a
  # temp file instead of either.
  sed '/^# --- Microsoft Sentinel Data Forwarding/,/^# }$/d' "${TFVARS_FILE}" > "${TFVARS_FILE}.tmp" \
    && mv "${TFVARS_FILE}.tmp" "${TFVARS_FILE}"

  cat >> "${TFVARS_FILE}" << EOF

# --- Microsoft Sentinel Data Forwarding -------------------------------------
# The application secret lives in the ${CUSTOMER} GitHub Environment as
# SENTINEL_APP_SECRET, not here. It is write-only, so rotating it means
# updating that secret AND incrementing app_secret_version below. The version
# bump is the only signal Terraform gets that anything changed.

sentinel = {
  directory_id             = "${DIRECTORY_ID}"
  application_id           = "${APPLICATION_ID}"
  data_collection_endpoint = "${DATA_COLLECTION_ENDPOINT}"
  alerts_rule_id           = "${ALERTS_RULE_ID}"
  alerts_stream_name       = "${ALERTS_STREAM_NAME}"
  telemetry_rule_id        = "${TELEMETRY_RULE_ID}"
  telemetry_stream_name    = "${TELEMETRY_STREAM_NAME}"
  app_secret_version       = "1"
}
EOF

  # --- Branch and pull request ----------------------------------------------
  BRANCH="enable-data-forwarding-sentinel/${CUSTOMER}"

  echo "==> Creating branch and committing changes..."
  git branch -D "${BRANCH}" 2>/dev/null || true
  git push origin --delete "${BRANCH}" 2>/dev/null || true
  git checkout -b "${BRANCH}"
  git add "${TFVARS_FILE}"
  git commit -m "feat: enable Sentinel data forwarding for ${CUSTOMER}"
  git push -u origin "${BRANCH}"

  echo "==> Opening pull request..."
  PR_ARGS=(
    --repo "${REPO}"
    --base main
    --head "${BRANCH}"
    --title "Enable Sentinel data forwarding: ${CUSTOMER}"
    --body "Enables Microsoft Sentinel data forwarding for **${CUSTOMER}**.

| Setting | Value |
|---------|-------|
| **Directory ID** | \`${DIRECTORY_ID}\` |
| **Application ID** | \`${APPLICATION_ID}\` |
| **Data Collection Endpoint** | \`${DATA_COLLECTION_ENDPOINT}\` |
| **Alerts Rule ID** | \`${ALERTS_RULE_ID}\` |
| **Alerts Stream Name** | \`${ALERTS_STREAM_NAME}\` |
| **Telemetry Rule ID** | \`${TELEMETRY_RULE_ID}\` |
| **Telemetry Stream Name** | \`${TELEMETRY_STREAM_NAME}\` |

The application secret is stored as \`SENTINEL_APP_SECRET\` in the \`${CUSTOMER}\` GitHub Environment.

## Checklist
- [ ] Plan output shows the data forwarding resource being created
- [ ] Azure Data Collection Rules are configured and the app registration has permission to write to them
- [ ] Confirm data arrives in Sentinel after the apply"
  )

  if [ -n "${REVIEWERS}" ]; then
    PR_ARGS+=(--reviewer "${REVIEWERS}")
  fi

  gh pr create "${PR_ARGS[@]}"

  echo
  echo "==> Done. Review the pull request and check the plan output."
fi
