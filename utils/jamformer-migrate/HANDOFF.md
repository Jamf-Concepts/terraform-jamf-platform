# jamformer-migrate — Next Phase Handoff

## Context

We are building a Go CLI tool called `jamformer-migrate` that migrates Terraform projects from the `deploymenttheory/jamfpro` provider to the `Jamf-Concepts/jamfplatform` provider. The tool lives at:

```
/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/utils/jamformer-migrate/
```

The repo is on branch `ref-jamfplatform-onboarder`. All commits go to that branch.

## Authoritative spec

Read this document in full before doing anything else — it is the definitive mapping reference for every resource type:

```
/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/utils/plan-to-improve-our-provider-converter.md
```

Provider example `.tf` files for ground truth:
- Old provider: `/Users/admin/Documents/GitHub/community/terraform-provider-jamfpro/examples/resources/`
- New provider: `/Users/admin/Documents/GitHub/jamf-concepts/terraform-provider-jamfplatform/examples/resources/`

Both repos are on main and up to date.

## What was completed (commit `fa4eb77`)

**All four tiers are scaffolded in `mapping.go` and `transform.go`.** The full registry of ~50 resource mappings is defined. The following are fully implemented and have passing golden-file tests:

- **Scaffold**: CLI (`main.go`), file walker, hclwrite parse/write loop, report builder, branch guard, `--dry-run`/`--report`/`--resources`/`--no-state`/`--force` flags
- **Tier 1** (7 resources): pure type-rename, no attr changes — `category`, `department`, `site`, `dock_item`, `api_role`, `access_management_settings`, `impact_alert_notification_settings`
- **Tier 2** (partial): `jamfpro_script` → `jamfplatform_pro_script` (param renames, priority enum, drop category_id); `jamfpro_api_integration` → `jamfplatform_pro_api_client` (authorization_scopes→api_roles, credential_rotation injection)
- **Tier 4** (6 sources → `jamfplatform_device_group`): criteria block → list-of-objects conversion, `.id` → `.jamf_pro_id` cross-reference rewrite via `rewriteFileText()`, static group UUID warning

**Golden tests passing**: `tier1_renames`, `script`, `api_client`, `smart_computer_group` (which also exercises macOS config profile structural transform in the same file).

**Key technical decisions already locked in:**
- `orderedAttrNames(body)` helper extracts attribute names in document order by scanning the token stream with `hclsyntax.TokenIdent` + `hclsyntax.TokenEqual` — essential to avoid Go map non-determinism in output
- String literal transforms (e.g. priority enum `"Before"` → `"BEFORE"`) use `replaceStringLiteral()` which re-parses a minimal HCL fragment — necessary because hclwrite represents `"Before"` as 3 tokens (OQuote, QuotedLit, CQuote), not one
- `rewriteFileText()` handles cross-reference expression rewrites (`.id` → `.jamf_pro_id`) at the text level after AST rewriting, using a pre-compiled regex `deviceGroupIDRe`

## File structure

```
utils/jamformer-migrate/
├── main.go                          # CLI entry point
├── go.mod                           # module: github.com/jamf/jamformer-migrate
├── migrate/
│   ├── mapping.go                   # ResourceMapping registry (all tiers fully declared)
│   ├── transform.go                 # HCL AST rewrite engine (1313 lines)
│   ├── migrate.go                   # Orchestrator: walk files, apply transforms, write output
│   ├── report.go                    # Migration report builder
│   ├── migrate_test.go              # Golden-file test harness (-update flag)
│   └── testdata/
│       ├── tier1_renames/           input.tf + golden.tf
│       ├── script/                  input.tf + golden.tf
│       ├── api_client/              input.tf + golden.tf
│       └── smart_computer_group/   input.tf + golden.tf (also tests macOS profile + static group)
```

## Current test state

```
go test ./migrate/ -run TestGolden -v
```

All 4 test suites PASS. Run from `utils/jamformer-migrate/`.

## What needs to be done next

Work through the plan's implementation order, picking up at **step 4**. The structural transform functions are all stubbed in `transform.go` — they need to be validated against the real provider examples and have golden-file tests added for each.

### Step 4 — Tier 2 remaining (verify transforms work, add golden tests)

These are all declared in `mapping.go` with transform functions in `transform.go`, but have no golden tests yet:
- `jamfpro_building` → underscore renames (`street_address1` → `street_address_1`)
- `jamfpro_network_segment` → drop attrs
- `jamfpro_computer_extension_attribute` / `jamfpro_mobile_device_extension_attribute` → inventory_display rename
- `jamfpro_allowed_file_extension` → strip leading dot from extension value
- `jamfpro_printer` → category_name → category
- `jamfpro_client_checkin` → hook renames + drop
- `jamfpro_webhook`, `jamfpro_jamf_protect`, `jamfpro_smtp_server` → WriteOnly injection
- `jamfpro_jamf_connect` → profile_id rename + review flag
- `jamfpro_local_admin_password_settings` → rotation interval renames + review flag
- `jamfpro_app_installer` → drop attrs, add app_title_name, deployment_type enum

For each: read the real provider example `.tf` files from both old and new provider dirs, create `testdata/<name>/input.tf` from the old example, create `testdata/<name>/golden.tf` as the expected output, run `go test ./migrate/ -run TestGolden/<name> -update` to generate the golden, then verify the golden matches what the new provider example shows.

### Step 5 — Tier 3: macOS and mobile config profiles

The `transformConfigProfile` function already exists in `transform.go`. It handles `general = {}` wrapping and `scope = { targets = {} }` restructuring. Verify it is correct against:
- `/Users/admin/Documents/GitHub/community/terraform-provider-jamfpro/examples/resources/jamfpro_macos_configuration_profile_plist/`
- `/Users/admin/Documents/GitHub/jamf-concepts/terraform-provider-jamfplatform/examples/resources/jamfplatform_pro_macos_configuration_profile/`

Add golden tests for both macOS and mobile profiles, including `self_service` block restructuring and `categories` list conversion (the plan has the full self_service schema).

### Step 6 — Tier 3: Policy

The most complex transform. `transformPolicy` is stubbed and handles the outer structure. The `payloads` unwrapping (`transformPolicyPayloads`) is implemented but needs verification. Reference:
- `/Users/admin/Documents/GitHub/community/terraform-provider-jamfpro/examples/resources/jamfpro_policy/`
- `/Users/admin/Documents/GitHub/jamf-concepts/terraform-provider-jamfplatform/examples/resources/jamfplatform_pro_policy/`

Use the real example files as input/golden fixtures. The policy transform is the most likely to have edge cases — test with a policy that has packages, scripts, and scope.

### Step 7 — Tier 3 remaining

In order:
- `jamfpro_package` → `transformPackage` (attr drops + display_name rename)
- `jamfpro_disk_encryption_configuration` → `transformDiskEncryption` (block→object + WO)
- `jamfpro_account` / `jamfpro_account_group` → `transformAccount`/`transformAccountGroup` (name→username, privilege restructuring)
- `jamfpro_ldap_server` → `transformLDAPServer` (major restructuring into connection_settings + mappings_for_users)
- `jamfpro_restricted_software` → `transformRestrictedSoftware`
- `jamfpro_computer_inventory_collection_settings` → `transformInventoryCollection`
- `jamfpro_computer_prestage_enrollment` / `jamfpro_mobile_device_prestage_enrollment` → prestage transforms
- `jamfpro_advanced_computer_search` / `jamfpro_advanced_mobile_device_search` → criteria restructuring (same pattern as device groups but different field names)
- `jamfpro_enrollment_customization` → pane block → list transform
- `jamfpro_sso_settings` → block→object + WO

### Step 8 — End-to-end validation

Run the tool against the real modules directory:

```
/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/
```

on a throwaway branch to see how it performs on real-world TF. Compare output against the already-migrated state on `ref-jamfplatform-onboarder` (the modules were partially migrated by the Python script previously — the Go tool should produce equivalent or better output from the raw `jamfpro_*` source).

### Step 9 — Skipped-resource warnings, report polish, exit codes

The `SkipReason` entries in `mapping.go` are already registered. Verify the report output for skipped resources looks right. Add a golden test that exercises a file containing a `jamfpro_engage_settings` resource.

## Key constraints to remember

1. **No regex against raw file text for resource detection** — always use hclwrite AST. The only text-level substitution allowed is `rewriteFileText()` for cross-reference rewrites (expressions in values like for_each lists that hclwrite can't reach).
2. **`orderedAttrNames(body)`** must be used any time you iterate `body.Attributes()` and the order matters for output — map iteration is random in Go.
3. **String literal transforms** must use `replaceStringLiteral()` — not byte-level token manipulation.
4. **WriteOnly fields**: every resource with a password/secret must have `*_wo_version = 1` injected after the secret attr. The full list is in the plan.
5. **Golden files reflect actual hclwrite output** — hclwrite's `SetAttributeRaw` appends renamed attrs to the body end. Golden files should reflect this, not the "ideal" human-written order. Use `-update` to generate goldens from the engine, then verify correctness manually.
6. **The `blockBodyToObjectLiteral` helper** in transform.go serializes a body's attrs as a `{ key = val }` literal for use as an attribute value. This is the standard pattern for block→object conversion throughout Tier 3.
