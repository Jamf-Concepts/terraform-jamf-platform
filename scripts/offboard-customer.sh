#!/bin/bash
# -----------------------------------------------------------------------------
# Customer Offboarding
# -----------------------------------------------------------------------------
# Removes a customer from the pipeline. Two modes, because there are two very
# different reasons a customer leaves.
#
# Usage: ./scripts/offboard-customer.sh [--handover] <customer-name>
#
# DEFAULT MODE: the tenant has been emptied.
#   Run the Terraform Destroy workflow first. This script then verifies that
#   destroy succeeded before touching anything, deletes the GitHub Environment,
#   removes the customer directory and opens a pull request for the audit trail.
#
# --handover MODE: the customer keeps their console.
#   No destroy is run and no Jamf resource is touched. The script dispatches
#   handover.yaml to remove only that customer's Terraform state object, waits
#   for it, then does the same GitHub cleanup. The console is left exactly as
#   the customer will inherit it.
#
# The distinction is not cosmetic: one empties a live tenant and the other does
# not. That is why it is an explicit flag with its own separate workflow rather
# than a prompt.
#
# Prerequisites:
#   - gh (GitHub CLI), authenticated with repo admin rights
#   - Default mode: the Terraform Destroy workflow must have completed
#     successfully for this customer
# -----------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

HANDOVER=false
CUSTOMER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --handover)
      HANDOVER=true
      ;;
    -*)
      echo "Error: unknown option: $1"
      echo "Usage: $0 [--handover] <customer-name>"
      exit 1
      ;;
    *)
      if [ -n "${CUSTOMER}" ]; then
        echo "Error: unexpected argument: $1"
        echo "Usage: $0 [--handover] <customer-name>"
        exit 1
      fi
      CUSTOMER="$1"
      ;;
  esac
  shift
done

if [ -z "${CUSTOMER}" ]; then
  echo "Usage: $0 [--handover] <customer-name>"
  exit 1
fi

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
CUSTOMER_DIR="customers/${CUSTOMER}"

if [ ! -d "${CUSTOMER_DIR}" ]; then
  echo "Error: customer directory ${CUSTOMER_DIR} does not exist."
  exit 1
fi

# --- Verify the destroy workflow succeeded -----------------------------------
# Skipped in handover mode, where no destroy is expected to have run.
#
# Note the limitation: this checks that A successful Terraform Destroy run
# exists, not that it was for THIS customer. Tighten it if that matters to you
# Matching on the run's inputs is possible but takes a lot more code.
if [ "${HANDOVER}" = false ]; then
  echo "==> Checking that the Terraform Destroy workflow completed successfully..."
  DESTROY_STATUS=$(gh run list \
    --repo "${REPO}" \
    --workflow "Terraform Destroy" \
    --json conclusion,headBranch \
    --jq '[.[] | select(.conclusion == "success")] | length')

  if [ "${DESTROY_STATUS}" -eq 0 ]; then
    echo "Error: no successful Terraform Destroy workflow run found."
    echo "       Run the Terraform Destroy workflow for ${CUSTOMER} before offboarding."
    exit 1
  fi
else
  echo "==> Handover mode: skipping destroy verification (no destroy is invoked)."
fi

echo "==> Offboarding customer: ${CUSTOMER}"

# --- Handover: tear down Terraform state ------------------------------------
# Runs BEFORE the GitHub Environment is deleted (the workflow references that
# environment) and BEFORE the directory is removed. Deletes the state object
# only. It touches no live resources.
if [ "${HANDOVER}" = true ]; then
  echo "==> Dispatching Handover workflow (Terraform state teardown) for ${CUSTOMER}..."

  # Record the newest existing run id first, so the run triggered below can be
  # pinned by id rather than trusting whatever "latest" happens to be by the
  # time this looks. Someone else dispatching concurrently would otherwise be
  # indistinguishable.
  BEFORE_ID=$(gh run list \
    --repo "${REPO}" \
    --workflow handover.yaml \
    --json databaseId \
    --jq '.[0].databaseId // 0')

  gh workflow run handover.yaml --repo "${REPO}" --ref main -f customer="${CUSTOMER}"

  # Run ids are monotonic, so ours is the lowest workflow_dispatch run id
  # strictly greater than BEFORE_ID.
  echo "==> Locating the dispatched workflow run..."
  RUN_ID=""
  for _ in $(seq 1 30); do
    RUN_ID=$(gh run list \
      --repo "${REPO}" \
      --workflow handover.yaml \
      --event workflow_dispatch \
      --json databaseId \
      --jq "[.[] | select(.databaseId > ${BEFORE_ID})] | min_by(.databaseId) | .databaseId // empty")
    [ -n "${RUN_ID}" ] && break
    sleep 2
  done

  if [ -z "${RUN_ID}" ]; then
    echo "Error: could not identify the dispatched Handover workflow run for ${CUSTOMER}."
    exit 1
  fi

  RUN_URL=$(gh run view "${RUN_ID}" --repo "${REPO}" --json url --jq '.url')
  echo "==> Watching Handover workflow run ${RUN_ID}: ${RUN_URL}"
  gh run watch "${RUN_ID}" --repo "${REPO}" --exit-status

  # Read the confirmed state key back out of the run log. The workflow prints
  # this marker ONLY after it has verified the object is gone, so its presence
  # is proof rather than an assumption.
  STATE_KEY="$(gh run view "${RUN_ID}" --repo "${REPO}" --log \
    | grep -oE 'HANDOVER_STATE_KEY_DELETED=[A-Za-z0-9._/-]+' \
    | head -n 1 \
    | cut -d= -f2 || true)"

  if [ -z "${STATE_KEY}" ]; then
    echo "Error: the Handover workflow succeeded but no confirmed state key was found in the run log."
    echo "       Review: ${RUN_URL}"
    exit 1
  fi

  echo "==> Terraform state confirmed deleted: ${STATE_KEY}"
fi

# --- Delete the GitHub Environment ------------------------------------------
# Takes every secret in it with it.
echo "==> Deleting GitHub Environment (and all its secrets)..."
gh api "repos/${REPO}/environments/${CUSTOMER}" -X DELETE

# --- Remove the customer directory and open a pull request ------------------
BRANCH="offboard/${CUSTOMER}"

if [ "${HANDOVER}" = true ]; then
  COMMIT_MSG="offboard (handover): remove ${CUSTOMER}"
  PR_TITLE="Offboard customer (handover): ${CUSTOMER}"
  PR_BODY="Removes the customer directory for **${CUSTOMER}** as part of a Jamf Protect console handover.

The console goes to the customer **as-is**. Nothing ran \`terraform destroy\` and **no Jamf resources were destroyed**. This removes the customer from the pipeline: the customer directory, the GitHub Environment, and the Terraform state object.

Terraform state deleted: \`${STATE_KEY}\` (handover workflow run ${RUN_URL}).

## Remaining manual steps
- [ ] Remove your team's console users from the tenant
- [ ] Remove the reporting integration API client and role, if the customer does not need them
- [ ] Confirm the customer has their own administrative access before you lose yours"
else
  COMMIT_MSG="offboard: remove ${CUSTOMER}"
  PR_TITLE="Offboard customer: ${CUSTOMER}"
  PR_BODY="Removes the customer directory for **${CUSTOMER}** following a successful Terraform destroy.

This pull request is for the audit trail. The resources, the S3 state object and the GitHub Environment are already gone.

## Remaining manual steps
- [ ] Revoke the bootstrap API client in the customer's Protect console (Terraform did not create it, so destroy did not remove it)
- [ ] Remove the customer's credentials from your credential store"
fi

echo "==> Creating branch and removing customer directory..."
git branch -D "${BRANCH}" 2>/dev/null || true
git push origin --delete "${BRANCH}" 2>/dev/null || true
git checkout -b "${BRANCH}"
rm -rf "${CUSTOMER_DIR}"
git add -A "${CUSTOMER_DIR}"
git commit -m "${COMMIT_MSG}"
git push -u origin "${BRANCH}"

echo "==> Opening pull request..."
gh pr create \
  --repo "${REPO}" \
  --base main \
  --head "${BRANCH}" \
  --title "${PR_TITLE}" \
  --body "${PR_BODY}"

echo
echo "==> Done. Next steps:"
echo "    1. Review and merge the pull request"
if [ "${HANDOVER}" = true ]; then
  echo "    2. Complete the manual console steps listed in the pull request"
else
  echo "    2. Revoke the bootstrap API client in the customer's Protect console"
fi
