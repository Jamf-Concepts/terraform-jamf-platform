This module deploys a macOS compliance benchmark via the Jamf Compliance
Benchmarks Engine (`jamfplatform_cbengine_benchmark`), instead of
hand-authored scripts/profiles/policies as in `compliance-macOS-cis-level-1`.
The Engine deploys and manages the underlying artifacts in Jamf Pro directly.

Generic over `baseline_id` — accepts any baseline the Jamf Platform API
supports (e.g. `cis_lvl1`), not just CIS Level 1. Baseline IDs are
server-defined and not validated by the provider or this module; the caller
is responsible for passing one the tenant actually has available (the Jamf
Foundations onboarder discovers these live via the Platform API rather than
hardcoding a list).

Used by the Jamf Foundations onboarder. `compliance-macOS-cis-level-1`
remains in place for other onboarders that haven't migrated to this approach
yet.
