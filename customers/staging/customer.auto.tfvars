# -----------------------------------------------------------------------------
# Customer Configuration — staging
# -----------------------------------------------------------------------------
# `staging` is not a customer. It is a workspace with the same shape as one,
# pointed at a Jamf Protect tenant you own, and it is where module changes get
# proved before they reach anybody's production console.
#
# It has its own GitHub Environment, its own credentials and its own state
# object, exactly like a customer — because a validation tenant configured
# differently from production validates nothing.
#
# How it is treated differently:
#   - Pull requests into the `staging` branch plan against this workspace only.
#   - Merges to `staging` apply against this workspace only.
#   - It is EXCLUDED from drift detection: while a change is being developed,
#     staging is expected to be ahead of `main`, so drift here is the normal
#     state rather than a signal.
#   - It IS included in out-of-band resource detection. It is a real tenant, so
#     something appearing in its console that Terraform did not create is worth
#     knowing about.
#
# Keep this on the standard tier unless you are specifically validating an
# enhanced-tier change. Testing on the tier most of your customers run is
# usually more useful than testing on the largest one.
# -----------------------------------------------------------------------------

product_tier = "standard"
