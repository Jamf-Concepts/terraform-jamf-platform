This module deploys the CIS Level 1 macOS compliance benchmark via the Jamf
Compliance Benchmarks Engine (`jamfplatform_cbengine_benchmark`), instead of
hand-authored scripts/profiles/policies as in `compliance-macOS-cis-level-1`.
The Engine deploys and manages the underlying artifacts in Jamf Pro directly.

Used by the Jamf Foundations onboarder. `compliance-macOS-cis-level-1` remains
in place for other onboarders that haven't migrated to this approach yet.
