#!/bin/bash
# -----------------------------------------------------------------------------
# Customer Onboarding
# -----------------------------------------------------------------------------
# One command takes a new customer from nothing to a pull request awaiting
# review. Two decisions: the name, and the tier.
#
# Usage: ./scripts/onboard-customer.sh <customer-name> [product-tier]
#
# Arguments:
#   customer-name   Lowercase, hyphenated identifier (e.g. example-customer).
#                   Becomes the directory name, the GitHub Environment name and
#                   the S3 state key — keep them identical.
#   product-tier    standard (default) or enhanced
#
# What it does, in order:
#   1. Create the GitHub Environment (the credential isolation boundary)
#   2. Prompt for Jamf Protect credentials
#   3. Delete the auto-created default plan and action configuration from the
#      tenant, via jamf-cli
#   4. Prompt for Jamf Pro admin credentials and get a bearer token
#   5. Check Jamf Protect is not already registered in that Jamf Pro instance
#   6. Create a scoped API role and OAuth2 client in Jamf Pro, via jamf-cli
#   7. Store all six secrets in the GitHub Environment — only after every
#      check above has passed
#   8. Scaffold the customer directory from customers/_template
#   9. Commit, push and open a pull request
#
# Ordering is deliberate. Nothing is written to GitHub until every validation
# has passed, so a failure halfway through leaves no half-configured customer
# behind.
#
# Prerequisites:
#   - gh (GitHub CLI), authenticated with repo admin rights
#   - jamf-cli    https://github.com/jamf-concepts/jamf-cli
#   - jq
#   - An API client created BY HAND in the customer's Jamf Protect console.
#     Terraform cannot create the credential it needs to authenticate with in
#     the first place — see modules/protect-baseline/api_client.tf.
#   - A Jamf Pro admin account for the customer's instance. Used once here to
#     bootstrap an OAuth2 client, and never stored.
#
# BEFORE FIRST USE: set the state bucket and region in
# customers/_template/terraform.tf, and set the STATE_BUCKET repository
# variable to match.
# -----------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

CUSTOMER="${1:?Usage: $0 <customer-name> [product-tier]}"
TIER="${2:-standard}"

# Resolve the repository from the environment, then from the local git remote.
# No hardcoded owner/name, so this works in a fork without editing.
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

# Optional: a GitHub team or user to request review from, e.g. "your-org/your-team".
# Set REVIEWERS in your environment to use it; unset means no reviewer is requested.
REVIEWERS="${REVIEWERS:-}"

# Optional: where you record credentials after onboarding (a password manager,
# a documentation system). Appears in the PR checklist only.
CREDENTIAL_STORE="${CREDENTIAL_STORE:-your credential store}"

if [[ ! "$CUSTOMER" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
  echo "Error: customer-name must be lowercase alphanumeric with dots, dashes or underscores."
  exit 1
fi

if [[ ! "$TIER" =~ ^(standard|enhanced)$ ]]; then
  echo "Error: product-tier must be one of: standard, enhanced"
  exit 1
fi

if [ -d "customers/${CUSTOMER}" ]; then
  echo "Error: customers/${CUSTOMER} already exists."
  exit 1
fi

for tool in gh jq jamf-cli; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Error: required tool '$tool' not found on PATH."; exit 1; }
done

echo "==> Onboarding customer: ${CUSTOMER} (tier: ${TIER}) in ${REPO}"

# --- 1. Create the GitHub Environment ---------------------------------------
# First, because it is the container every secret below goes into.
echo "==> Creating GitHub Environment..."
gh api "repos/${REPO}/environments/${CUSTOMER}" -X PUT --input - <<EOF
{}
EOF

# --- 2. Collect Jamf Protect credentials ------------------------------------
echo "==> Collecting Jamf Protect credentials..."
read -r -p "  → Protect tenant URL (e.g. https://example.protect.jamfcloud.com): " PROTECT_URL_VAL
read -r -p "  → API client ID: " PROTECT_CLIENT_ID_VAL
read -r -s -p "  → API client password: " PROTECT_CLIENT_PASSWORD_VAL
echo

# --- 3. Remove auto-created Protect defaults --------------------------------
# Every new Protect tenant ships with a "Default" plan and action
# configuration. The default plan syncs to Jamf Pro and creates an unscoped
# configuration profile, so both must go before Terraform runs — otherwise you
# spend the rest of the engagement fighting something you did not create.

echo "==> Removing default Protect plan (if present)..."
export JAMFPROTECT_URL="${PROTECT_URL_VAL}"
export JAMFPROTECT_CLIENT_ID="${PROTECT_CLIENT_ID_VAL}"
export JAMFPROTECT_CLIENT_SECRET="${PROTECT_CLIENT_PASSWORD_VAL}"

if jamf-cli protect plans get "Default" -o json >/dev/null 2>&1; then
  jamf-cli protect plans delete "Default" --yes
else
  echo "  ✓ Already removed — skipping."
fi

echo "==> Removing default Protect action configuration (if present)..."
if jamf-cli protect action-configs get "Default" -o json >/dev/null 2>&1; then
  jamf-cli protect action-configs delete "Default" --yes
else
  echo "  ✓ Already removed — skipping."
fi

# Drop the Protect credentials out of the environment now they are no longer
# needed, so they are not inherited by the git and gh invocations below.
unset JAMFPROTECT_URL JAMFPROTECT_CLIENT_ID JAMFPROTECT_CLIENT_SECRET

# --- 4. Collect Jamf Pro admin credentials ----------------------------------
# Temporary. Used to obtain a bearer token and bootstrap an OAuth2 API client,
# then discarded when this script exits. They are never written anywhere.
read -r -p "  → Jamf Pro URL (e.g. https://example.jamfcloud.com): " JAMF_PRO_URL
JAMF_PRO_URL="${JAMF_PRO_URL%/}"
read -r -p "  → Jamf Pro username: " JAMF_PRO_USER
read -r -s -p "  → Jamf Pro password: " JAMF_PRO_PASSWORD
echo

echo "==> Obtaining bearer token from Jamf Pro..."
AUTH_RESPONSE=$(curl -s -X POST -u "${JAMF_PRO_USER}:${JAMF_PRO_PASSWORD}" \
  "${JAMF_PRO_URL}/api/v1/auth/token")
BEARER_TOKEN=$(echo "${AUTH_RESPONSE}" | jq -r '.token' 2>/dev/null)

if [ -z "${BEARER_TOKEN}" ] || [ "${BEARER_TOKEN}" == "null" ]; then
  echo "Error: failed to obtain bearer token from Jamf Pro. Check credentials and URL."
  exit 1
fi

# --- 5. Check for an existing Protect registration --------------------------
# Registering twice conflicts, so abort rather than stomp on something already
# in place. Exit code 4 from jamf-cli means "not found", which is the expected
# state for a new onboarding — the check passing looks like a failure if you
# are not expecting it.
rc=0
JAMF_URL="${JAMF_PRO_URL}" JAMF_TOKEN="${BEARER_TOKEN}" \
  jamf-cli pro jamf-protect get --no-input -o json 2>/dev/null || rc=$?

if [ "$rc" -eq 0 ]; then
  echo "Error: Jamf Protect is already registered in this Jamf Pro instance."
  echo "       Remove the existing registration before re-onboarding."
  exit 1
elif [ "$rc" -eq 4 ]; then
  echo "  ✓ No existing Protect registration found — proceeding."
else
  echo "Error: unexpected error checking Protect registration (exit code ${rc})."
  exit 1
fi

# --- 6. Create the Jamf Pro API role and OAuth2 client ----------------------
# Least privilege: exactly the privileges the jamfpro_jamf_protect resource
# needs, and nothing else. Both apply commands are idempotent, so re-running
# this script does not create duplicates.

echo "==> Creating Jamf Pro API role and OAuth2 client..."
echo '{
  "displayName": "terraform-protect-registration",
  "privileges": [
    "Read Jamf Protect Deployments",
    "Read Jamf Protect Settings",
    "Update Jamf Protect Deployments",
    "Update Jamf Protect Settings",
    "Create Jamf Protect Deployments",
    "Delete Jamf Protect Deployments",
    "Jamf Protect Deployment Retry"
  ]
}' | JAMF_URL="${JAMF_PRO_URL}" JAMF_TOKEN="${BEARER_TOKEN}" \
  jamf-cli pro api-roles apply --yes --no-input >/dev/null

rc=0
INTEGRATION_RESPONSE=$(echo '{
  "displayName": "terraform-protect-registration",
  "authorizationScopes": ["terraform-protect-registration"],
  "enabled": true
}' | JAMF_URL="${JAMF_PRO_URL}" JAMF_TOKEN="${BEARER_TOKEN}" \
  jamf-cli pro api-integrations apply --yes --no-input -o json) || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "Error: failed to create API integration (exit code ${rc})."
  echo "${INTEGRATION_RESPONSE}"
  exit 1
fi

INTEGRATION_ID=$(echo "${INTEGRATION_RESPONSE}" | jq -r '.id')

if [ -z "${INTEGRATION_ID}" ] || [ "${INTEGRATION_ID}" == "null" ]; then
  echo "Error: API integration created but no ID returned."
  echo "${INTEGRATION_RESPONSE}"
  exit 1
fi

# The apply command does not return a secret, so credentials are generated
# separately against the integration's numeric ID. Using the ID rather than the
# name means a re-run always produces valid credentials for the right client.
rc=0
CREDENTIALS_RESPONSE=$(JAMF_URL="${JAMF_PRO_URL}" JAMF_TOKEN="${BEARER_TOKEN}" \
  jamf-cli pro api-integrations client-credentials "${INTEGRATION_ID}" --no-input -o json) || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "Error: failed to generate client credentials (exit code ${rc})."
  echo "${CREDENTIALS_RESPONSE}"
  exit 1
fi

JPRO_CLIENT_ID=$(echo "${CREDENTIALS_RESPONSE}" | jq -r '.clientId')
JPRO_CLIENT_SECRET=$(echo "${CREDENTIALS_RESPONSE}" | jq -r '.clientSecret')

if [ -z "${JPRO_CLIENT_ID}" ] || [ "${JPRO_CLIENT_ID}" == "null" ] || \
   [ -z "${JPRO_CLIENT_SECRET}" ] || [ "${JPRO_CLIENT_SECRET}" == "null" ]; then
  echo "Error: credentials generated but clientId/clientSecret missing from response."
  echo "${CREDENTIALS_RESPONSE}"
  exit 1
fi

# --- 7. Store secrets in the GitHub Environment -----------------------------
# Only now, with everything validated. The Protect URL is a variable rather
# than a secret: it is not sensitive, and having it readable makes run logs and
# summaries useful.
echo "==> Storing environment variable and secrets..."
gh variable set PROTECT_URL --env "${CUSTOMER}" --repo "${REPO}" --body "${PROTECT_URL_VAL}"
echo "${PROTECT_CLIENT_ID_VAL}"       | gh secret set PROTECT_CLIENT_ID       --env "${CUSTOMER}" --repo "${REPO}"
echo "${PROTECT_CLIENT_PASSWORD_VAL}" | gh secret set PROTECT_CLIENT_PASSWORD --env "${CUSTOMER}" --repo "${REPO}"
echo "${JAMF_PRO_URL}"                | gh secret set JPRO_URL                --env "${CUSTOMER}" --repo "${REPO}"
echo "${JPRO_CLIENT_ID}"              | gh secret set JPRO_CLIENT_ID           --env "${CUSTOMER}" --repo "${REPO}"
echo "${JPRO_CLIENT_SECRET}"          | gh secret set JPRO_CLIENT_SECRET       --env "${CUSTOMER}" --repo "${REPO}"

# --- 8. Scaffold the customer directory -------------------------------------
TEMPLATE_DIR="customers/_template"
CUSTOMER_DIR="customers/${CUSTOMER}"

echo "==> Scaffolding customer directory from template..."
cp -r "${TEMPLATE_DIR}" "${CUSTOMER_DIR}"

# Portable in-place sed: BSD sed (macOS) requires an argument to -i, GNU sed
# requires there to be none. Write to a temp file and move instead.
for f in "${CUSTOMER_DIR}"/*.tf "${CUSTOMER_DIR}"/*.tfvars; do
  sed "s/<CUSTOMER_NAME>/${CUSTOMER}/g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

sed "s/^product_tier = \"standard\"/product_tier = \"${TIER}\"/" \
  "${CUSTOMER_DIR}/customer.auto.tfvars" > "${CUSTOMER_DIR}/customer.auto.tfvars.tmp" \
  && mv "${CUSTOMER_DIR}/customer.auto.tfvars.tmp" "${CUSTOMER_DIR}/customer.auto.tfvars"

# --- 9. Commit, push, open a pull request -----------------------------------
BRANCH="new-customer/${CUSTOMER}"

echo "==> Creating branch and committing customer directory..."
git branch -D "${BRANCH}" 2>/dev/null || true
git push origin --delete "${BRANCH}" 2>/dev/null || true
git checkout -b "${BRANCH}"
git add "${CUSTOMER_DIR}"
git commit -m "onboard: add ${CUSTOMER}"
git push -u origin "${BRANCH}"

echo "==> Opening pull request..."
PR_ARGS=(
  --repo "${REPO}"
  --base main
  --head "${BRANCH}"
  --title "Onboard customer: ${CUSTOMER}"
  --body "Adds the customer directory for **${CUSTOMER}**.

| Detail | Value |
|--------|-------|
| **Protect URL** | \`${PROTECT_URL_VAL}\` |
| **Product tier** | \`${TIER}\` |

Credentials are stored in the \`${CUSTOMER}\` GitHub Environment. Nothing
sensitive is in this diff.

## Checklist
- [ ] Review \`${CUSTOMER_DIR}/customer.auto.tfvars\` — add any USB exceptions or exception sets
- [ ] Check the plan output posted below
- [ ] After merge and a successful apply, record the API credentials in ${CREDENTIAL_STORE}"
)

if [ -n "${REVIEWERS}" ]; then
  PR_ARGS+=(--reviewer "${REVIEWERS}")
fi

gh pr create "${PR_ARGS[@]}"

echo
echo "==> Done. Next steps:"
echo "    1. Review the pull request and check the plan output"
echo "    2. Merge — the apply workflow provisions the tenant and registers Protect in Jamf Pro"
echo "    3. Record the API credentials in ${CREDENTIAL_STORE}"
