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

## What was completed (Steps 1–4)

**All four tiers are scaffolded in `mapping.go` and `transform.go`.** The full registry of ~50 resource mappings is defined. The following are fully implemented with passing golden-file tests:

**Scaffold** (Step 1): CLI (`main.go`), file walker, hclwrite parse/write loop, report builder, branch guard, `--dry-run`/`--report`/`--resources`/`--no-state`/`--force` flags

**Tier 1** (Step 2, 7 resources): pure type-rename — `category`, `department`, `site`, `dock_item`, `api_role`, `access_management_settings`, `impact_alert_notification_settings`

**Tier 4** (Step 3, 6 resources): `jamfplatform_device_group` folding — criteria block → list-of-objects conversion, `.id` → `.jamf_pro_id` cross-reference rewrite via `rewriteFileText()`, static group UUID warning

**Tier 2 complete** (Step 4, 13 resources): All Tier 2 resources now have golden tests:
- `jamfpro_building` → underscore renames
- `jamfpro_network_segment` → drop attrs
- `jamfpro_computer_extension_attribute` → `inventory_display_type`/`script_contents` renames
- `jamfpro_mobile_device_extension_attribute` → `inventory_display_type` rename
- `jamfpro_allowed_file_extension` → strip leading dot from extension value
- `jamfpro_printer` → `category_name` → `category`
- `jamfpro_client_checkin` → hook renames + drop `enable_local_configuration_profiles`
- `jamfpro_webhook` → `password_wo_version = 1` injection
- `jamfpro_jamf_protect` → `protect_url` → `api_url` + `password_wo_version = 1`
- `jamfpro_jamf_connect` → `config_profile_uuid` → `profile_id` + review flag
- `jamfpro_local_admin_password_settings` → rotation interval renames + review flag
- `jamfpro_smtp_server` → sub-blocks → object attrs + WO version injection inside credential objects
- `jamfpro_api_integration` → `api_roles` rename + `credential_rotation` injection
- `jamfpro_script` → param renames, priority enum, drop `category_id`
- `jamfpro_app_installer` → drop attrs, `app_title_name` injection, `deployment_type` enum, sub-blocks → object attrs

**Golden tests passing**: 17 test suites total (run `go test ./migrate/ -run TestGolden -v` from `utils/jamformer-migrate/`).

## Key technical decisions already locked in

- `orderedAttrNames(body)` extracts attribute names in document order by scanning the token stream — essential to avoid Go map non-determinism in output
- `replaceStringLiteral()` handles string literal transforms (re-parses a minimal HCL fragment) because hclwrite represents `"Before"` as 3 tokens
- `rewriteFileText()` handles cross-reference expression rewrites (`.id` → `.jamf_pro_id`) at text level after AST rewriting
- `blockBodyToObjectLiteral()` uses `orderedAttrNames` for deterministic attribute order in generated object literals
- `applyAttrMappings` is called before `StructuralTransform` in `applyMapping` so Tier 2 resources with both `Attrs`/`DropAttrs` and a `StructuralTransform` work correctly
- `transformSMTPServer` converts connection/credential sub-blocks to object attrs and injects WO version fields inside the credential objects

## File structure

```
utils/jamformer-migrate/
├── main.go                          # CLI entry point
├── go.mod                           # module: github.com/jamf/jamformer-migrate
├── migrate/
│   ├── mapping.go                   # ResourceMapping registry (all tiers fully declared)
│   ├── transform.go                 # HCL AST rewrite engine (~1350 lines)
│   ├── migrate.go                   # Orchestrator: walk files, apply transforms, write output
│   ├── report.go                    # Migration report builder
│   ├── migrate_test.go              # Golden-file test harness (-update flag)
│   └── testdata/
│       ├── tier1_renames/
│       ├── script/
│       ├── api_client/
│       ├── smart_computer_group/    # also exercises macOS config profile structural transform
│       ├── building/
│       ├── network_segment/
│       ├── computer_extension_attribute/
│       ├── mobile_device_extension_attribute/
│       ├── allowed_file_extension/
│       ├── printer/
│       ├── client_checkin/
│       ├── webhook/
│       ├── jamf_protect/
│       ├── jamf_connect/
│       ├── local_admin_password_settings/
│       ├── smtp_server/
│       └── app_installer/
```

## Current test state

```
go test ./migrate/ -run TestGolden -v
```

All 17 test suites PASS. Run from `utils/jamformer-migrate/`.

## What needs to be done next

Work through the plan's implementation order, picking up at **Step 5**.

### Step 5 — Tier 3: macOS and mobile config profiles

The `transformConfigProfile` function already exists in `transform.go` and handles:
- `general = {}` wrapping
- `scope = { targets = {} }` restructuring
- `all_jss_users` drop from scope
- `payload_validate` / `site_id` drop
- `deployment_method` → `distribution_method` rename (mobile only)

**What is NOT yet implemented** (stubs exist, marked `// TODO`):
- `self_service { ... }` block → `self_service = { ... }` object attr restructuring
  - `force_users_to_view_description` → `ensure_users_view_description`
  - `self_service_category { ... }` block → `categories = [ { id, display_in, feature_in } ]` list
- Cross-reference rewrite: device group `.id` → `.jamf_pro_id` in scope

Verify `transformConfigProfile` against:
- Old: `/Users/admin/Documents/GitHub/community/terraform-provider-jamfpro/examples/resources/jamfpro_macos_configuration_profile_plist/resource.tf`
- New: `/Users/admin/Documents/GitHub/jamf-concepts/terraform-provider-jamfplatform/examples/resources/jamfplatform_pro_macos_configuration_profile/resource.tf`
- Old mobile: `/Users/admin/Documents/GitHub/community/terraform-provider-jamfpro/examples/resources/jamfpro_mobile_device_configuration_profile_plist/resource.tf`
- New mobile: `/Users/admin/Documents/GitHub/jamf-concepts/terraform-provider-jamfplatform/examples/resources/jamfplatform_pro_mobile_device_configuration_profile/resource.tf`

Add golden tests for both `macos_config_profile` and `mobile_config_profile` in `testdata/`, including a resource with a `self_service` block and `scope` with group references.

### Step 6 — Tier 3: Policy

The most complex transform. `transformPolicy` is implemented in `transform.go` and handles:
- `general = {}` wrapping
- `scope = { targets = {} }`
- `self_service = {}` block → object
- `payloads` block unwrapping (via `transformPolicyPayloads`)
- `date_time_limitations` / `network_limitations` removal with report warning

**What `transformPolicyPayloads` does NOT yet handle well:**
- The `self_service { categories { ... } }` nested blocks → `self_service = { categories = [ { ... } ] }` list conversion (currently copies self_service attrs flat, doesn't restructure the categories sub-blocks)
- Verify against real examples

Reference:
- Old: `/Users/admin/Documents/GitHub/community/terraform-provider-jamfpro/examples/resources/jamfpro_policy/`
- New: `/Users/admin/Documents/GitHub/jamf-concepts/terraform-provider-jamfplatform/examples/resources/jamfplatform_pro_policy/`

Use the real example files as input/golden fixtures. Test with a policy that has packages, scripts, scope, and self_service with categories.

### Step 7 — Tier 3 remaining

In order (all have stub functions in `transform.go` — verify against real provider examples and add golden tests):

- `jamfpro_package` → `transformPackage` (attr drops + `display_name` rename)
- `jamfpro_disk_encryption_configuration` → `transformDiskEncryption` (block→object + WO)
- `jamfpro_account` → `transformAccount` (name→username, privilege restructuring, WO)
- `jamfpro_account_group` → `transformAccountGroup` (name→display_name, privilege restructuring)
- `jamfpro_ldap_server` → `transformLDAPServer` (major restructuring into connection_settings + mappings_for_users)
- `jamfpro_restricted_software` → `transformRestrictedSoftware`
- `jamfpro_computer_inventory_collection_settings` → `transformInventoryCollection`
- `jamfpro_computer_prestage_enrollment` / `jamfpro_mobile_device_prestage_enrollment` → prestage transforms
- `jamfpro_advanced_computer_search` / `jamfpro_advanced_mobile_device_search` → criteria restructuring
- `jamfpro_enrollment_customization` → pane block → list transform
- `jamfpro_sso_settings` → block→object + WO

### Step 8 — End-to-end validation

Run the tool against the real modules directory:

```
/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/
```

on a throwaway branch to see how it performs on real-world TF. Compare output against the already-migrated state on `ref-jamfplatform-onboarder`.

### Step 9 — Skipped-resource warnings, report polish, exit codes

The `SkipReason` entries in `mapping.go` are already registered. Verify the report output for skipped resources looks right. Add a golden test that exercises a file containing a `jamfpro_engage_settings` resource.

## Key constraints to remember

1. **No regex against raw file text for resource detection** — always use hclwrite AST. The only text-level substitution allowed is `rewriteFileText()` for cross-reference rewrites.
2. **`orderedAttrNames(body)`** must be used any time you iterate `body.Attributes()` and order matters — map iteration is random in Go. `blockBodyToObjectLiteral` already does this.
3. **String literal transforms** must use `replaceStringLiteral()` — not byte-level token manipulation.
4. **WriteOnly fields**: every resource with a password/secret must have `*_wo_version = 1` injected after the secret attr. The full list is in the plan.
5. **Golden files reflect actual hclwrite output** — `SetAttributeRaw` appends renamed attrs to the body end. Goldens reflect this ordering, not "ideal" human-written order. Use `-update` to generate goldens from the engine, then verify correctness manually.
6. **`blockBodyToObjectLiteral`** serializes a body's attrs as a `{ key = val }` literal in document order. Use this for all block→object conversions.
7. **`applyAttrMappings` is called before `StructuralTransform`** in `applyMapping` — don't duplicate attr-rename logic inside structural transform functions if it can be expressed as `Attrs`/`DropAttrs` in the mapping definition.
