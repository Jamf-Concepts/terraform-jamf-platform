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
#   4. Prompt for Jamf Platform API credentials
#   5. Check, via jamf-cli through the Platform gateway, that the tenant has no
#      existing Jamf Protect registration — which also proves the credentials
#      authenticate and carry the required privileges
#   6. Store all seven values in the GitHub Environment — only after every
#      check above has passed
#   7. Scaffold the customer directory from customers/_template
#   8. Commit, push and open a pull request
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
#   - A Jamf Platform API integration for the customer, scoped to a platform
#     environment and granted these permissions (see the
#     jamfplatform_pro_jamf_protect resource docs):
#         Deployment > Jamf Protect deployment > Read, Update
#         Infrastructure > Jamf Pro server URL > Read
#     NOT created by this script: Platform API integrations are created in the
#     Jamf Account portal (account.jamf.com), so bring one with you.
#     `jamf-cli platform setup` turns one into a local CLI profile if you also
#     want to drive the CLI interactively.
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

# --- 4. Collect Jamf Platform API credentials -------------------------------
# These reach the customer's Jamf Pro instance through the Platform API gateway.
# Note what identifies the customer here: a REGIONAL base URL plus a platform
# environment UUID, not a Jamf Pro hostname.
echo
echo "==> Collecting Jamf Platform API credentials..."
echo "    The API integration must already exist, with these permissions:"
echo "      Deployment > Jamf Protect deployment > Read, Update"
echo "      Infrastructure > Jamf Pro server URL > Read"
echo
read -r -p "  → Platform base URL (https://us.api.jamfcloud.com | eu | apac): " PLATFORM_BASE_URL_VAL
PLATFORM_BASE_URL_VAL="${PLATFORM_BASE_URL_VAL%/}"
read -r -p "  → Platform environment UUID: " PLATFORM_ENVIRONMENT_ID_VAL
read -r -p "  → Platform API client ID: " PLATFORM_CLIENT_ID_VAL
read -r -s -p "  → Platform API client secret: " PLATFORM_CLIENT_SECRET_VAL
echo

# Validate locally, before anything is stored. The same checks exist as
# variable validation in the module, but failing here is much cheaper than
# failing in CI after the secrets are already written and a PR is open.
if [[ ! "$PLATFORM_BASE_URL_VAL" =~ ^https://[a-z]+\.api\.jamfcloud\.com$ ]]; then
  echo "Error: '${PLATFORM_BASE_URL_VAL}' is not a Jamf Platform API gateway URL."
  echo "       Expected something like https://eu.api.jamfcloud.com, not a Jamf Pro tenant URL."
  exit 1
fi

if [[ ! "$PLATFORM_ENVIRONMENT_ID_VAL" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "Error: '${PLATFORM_ENVIRONMENT_ID_VAL}' is not a UUID."
  exit 1
fi

for var in PLATFORM_CLIENT_ID_VAL PLATFORM_CLIENT_SECRET_VAL; do
  if [ -z "${!var}" ]; then
    echo "Error: ${var%_VAL} must not be empty."
    exit 1
  fi
done

# --- Check for an existing Protect registration ------------------------------
# This matters: the registration is a singleton, and creating it over an
# existing one does NOT fail — the server overwrites it in place. So abort
# rather than stomp on something already configured.
#
# jamf-cli reaches the Jamf Pro API through the Platform gateway when given
# platform credentials. Its variable names differ from the Terraform provider's:
# JAMF_URL (set to the gateway base URL), JAMF_CLIENT_ID, JAMF_CLIENT_SECRET,
# JAMF_ENVIRONMENT_ID.
#
# This doubles as a live credential check. The validation above only checked the
# shape of what was typed, whereas this proves the credentials authenticate and
# carry the required permissions, before any secret is written to GitHub.
#
# --no-version-check: whether a registration exists does not depend on the
# tenant's Jamf Pro version, so skip it and avoid failing on an older tenant.
echo "==> Checking for an existing Jamf Protect registration..."
rc=0
JAMF_URL="${PLATFORM_BASE_URL_VAL}" \
JAMF_ENVIRONMENT_ID="${PLATFORM_ENVIRONMENT_ID_VAL}" \
JAMF_CLIENT_ID="${PLATFORM_CLIENT_ID_VAL}" \
JAMF_CLIENT_SECRET="${PLATFORM_CLIENT_SECRET_VAL}" \
  jamf-cli pro jamf-protect get --no-input --no-version-check -o json >/dev/null 2>&1 || rc=$?

case "${rc}" in
  0)
    echo "Error: Jamf Protect is already registered in this Jamf Pro tenant."
    echo "       Applying would overwrite that registration in place."
    echo "       Remove it first, or adopt it into state instead of onboarding fresh."
    exit 1
    ;;
  4)
    # not_found — the expected state for a new onboarding.
    echo "  ✓ No existing Protect registration found."
    ;;
  3)
    echo "Error: the Platform API credentials failed to authenticate (exit 3)."
    echo "       Check the client ID, secret, environment UUID and region base URL."
    exit 1
    ;;
  5)
    echo "Error: the Platform API integration authenticated but lacks the required permissions (exit 5)."
    echo "       It needs:"
    echo "         Deployment > Jamf Protect deployment > Read, Update"
    echo "         Infrastructure > Jamf Pro server URL > Read"
    exit 1
    ;;
  *)
    echo "Error: unexpected error checking the Protect registration (exit ${rc})."
    exit 1
    ;;
esac

# Resolve the Jamf Pro hostname behind the environment UUID and show it. A UUID
# typo that still authenticates would otherwise point this customer at the wrong
# instance, and nothing later would reveal it.
JAMF_PRO_URL=$(JAMF_URL="${PLATFORM_BASE_URL_VAL}" \
  JAMF_ENVIRONMENT_ID="${PLATFORM_ENVIRONMENT_ID_VAL}" \
  JAMF_CLIENT_ID="${PLATFORM_CLIENT_ID_VAL}" \
  JAMF_CLIENT_SECRET="${PLATFORM_CLIENT_SECRET_VAL}" \
  jamf-cli pro jamf-pro-server-url get --no-input --no-version-check --field url 2>/dev/null || true)

if [ -n "${JAMF_PRO_URL}" ]; then
  echo "  → This tenant is Jamf Pro: ${JAMF_PRO_URL}"
  read -r -p "  → Is that the right instance for ${CUSTOMER}? (type 'yes'): " CONFIRM_JPRO
  if [ "${CONFIRM_JPRO}" != "yes" ]; then
    echo "Aborted. Nothing was stored and no directory was created."
    exit 1
  fi
else
  JAMF_PRO_URL="unresolved"
  echo "  ! Could not resolve the Jamf Pro URL (needs Infrastructure > Jamf Pro server URL > Read). Continuing."
fi

# --- 5. Store secrets in the GitHub Environment -----------------------------
# Only now, with everything validated. URLs and the environment UUID are
# variables rather than secrets: they are identifiers, not credentials, and
# having them readable makes run logs and summaries useful.
echo "==> Storing environment variables and secrets..."
gh variable set PROTECT_URL       --env "${CUSTOMER}" --repo "${REPO}" --body "${PROTECT_URL_VAL}"
gh variable set PLATFORM_BASE_URL --env "${CUSTOMER}" --repo "${REPO}" --body "${PLATFORM_BASE_URL_VAL}"
gh variable set PLATFORM_ENVIRONMENT_ID --env "${CUSTOMER}" --repo "${REPO}" --body "${PLATFORM_ENVIRONMENT_ID_VAL}"
echo "${PROTECT_CLIENT_ID_VAL}"       | gh secret set PROTECT_CLIENT_ID       --env "${CUSTOMER}" --repo "${REPO}"
echo "${PROTECT_CLIENT_PASSWORD_VAL}" | gh secret set PROTECT_CLIENT_PASSWORD --env "${CUSTOMER}" --repo "${REPO}"
echo "${PLATFORM_CLIENT_ID_VAL}"      | gh secret set PLATFORM_CLIENT_ID      --env "${CUSTOMER}" --repo "${REPO}"
echo "${PLATFORM_CLIENT_SECRET_VAL}"  | gh secret set PLATFORM_CLIENT_SECRET  --env "${CUSTOMER}" --repo "${REPO}"

# --- 6. Scaffold the customer directory -------------------------------------
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

# --- 7. Commit, push, open a pull request -----------------------------------
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
| **Platform base URL** | \`${PLATFORM_BASE_URL_VAL}\` |
| **Platform environment ID** | \`${PLATFORM_ENVIRONMENT_ID_VAL}\` |
| **Jamf Pro** | \`${JAMF_PRO_URL}\` |
| **Product tier** | \`${TIER}\` |

Credentials are stored in the \`${CUSTOMER}\` GitHub Environment. Nothing
sensitive is in this diff.

## Checklist
- [ ] Review \`${CUSTOMER_DIR}/customer.auto.tfvars\` — add any USB exceptions or exception sets
- [ ] Check the plan output posted below, in particular that \`jamfplatform_pro_jamf_protect\` is being **created** and not replacing an existing registration
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
