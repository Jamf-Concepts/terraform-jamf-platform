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

## What was completed (Steps 1–7)

**All four tiers are scaffolded in `mapping.go` and `transform.go`.** The full registry of ~50 resource mappings is defined. The following are fully implemented with passing golden-file tests:

**Scaffold** (Step 1): CLI (`main.go`), file walker, hclwrite parse/write loop, report builder, branch guard, `--dry-run`/`--report`/`--resources`/`--no-state`/`--force` flags

**Tier 1** (Step 2, 7 resources): pure type-rename — `category`, `department`, `site`, `dock_item`, `api_role`, `access_management_settings`, `impact_alert_notification_settings`

**Tier 4** (Step 3, 6 resources): `jamfplatform_device_group` folding — criteria block → list-of-objects conversion, `.id` → `.jamf_pro_id` cross-reference rewrite via `rewriteFileText()`, static group UUID warning

**Tier 2 complete** (Step 4, 13 resources): All Tier 2 resources now have golden tests — see original handoff for full list.

**Tier 3 config profiles** (Step 5): `transformConfigProfile` fully implemented:
- `general = {}` wrapping, `payload_validate`/`site_id` drop, `all_jss_users` drop
- `scope = { targets = {}, exclusions = {} }` with group ref rewrites
- `self_service = { ..., ensure_users_view_description, categories = [...] }` — `force_users_to_view_description` rename + `self_service_category {}` blocks → list
- Golden tests: `macos_config_profile`, `mobile_config_profile`

**Tier 3 policy** (Step 6): `transformPolicy` fully implemented:
- `general = {}` wrapping, `date_time_limitations`/`network_limitations` drop with report warning
- `scope = { targets = {}, exclusions = {} }` with `all_jss_users` drop
- `self_service = { ..., categories = [...] }` — self_service_category blocks → list
- All payload sub-blocks unwrapped: `packages`, `scripts`, `printers`, `dock_items`, `maintenance`, `restart_options`, `files_and_processes`, `user_interaction`, `disk_encryption`, `local_accounts`, `management_account`, `directory_bindings`, `efi_password` (with WO versions)
- NOTE: old `scripts {}`/`printers {}`/`dock_items {}` blocks are each a SINGLE item, not containers
- NOTE: `open_firmware_efi_password {}` is the old block name (handled alongside `efi_password`)
- Golden test: `policy`

**Tier 3 remaining** (Step 7): All remaining Tier 3 resources fully implemented with golden tests:
- `jamfpro_package` → `transformPackage` (`package_name`→`display_name`, drops, `manifest_file_name`→`manifest_file_source`)
- `jamfpro_disk_encryption_configuration` → `transformDiskEncryption` (`institutional_recovery_key` block→object + WO)
- `jamfpro_account` → `transformAccount` (`name`→`username`, `email`→`email_address`, WO, privilege restructuring)
- `jamfpro_account_group` → `transformAccountGroup` (`name`→`display_name`, `identity_server_id`→`ldap_server_id`, privilege restructuring)
- `jamfpro_ldap_server` → `transformLDAPServer` (`name`→`display_name` in `connection_settings`, `server_type`→`directory_service`, `open_close_timeout`→`connection_timeout`, `map_object_class_to_any_or_all`→`object_class_limitation`, WO for password; `connection_settings` + `mappings_for_users` objects)
- `jamfpro_restricted_software` → `transformRestrictedSoftware` (`general = {}`, scope+exclusions; handles `site_id {}` block form)
- `jamfpro_computer_inventory_collection_settings` → `transformInventoryCollection` (nested block → flat attrs, `application_paths` blocks → list)
- `jamfpro_advanced_computer_search` → `transformAdvancedComputerSearch` (view_as/sort* drop, criteria→list; uses `transformAdvancedSearchCriteria` which keeps `name`/`search_type` attr names)
- `jamfpro_advanced_mobile_device_search` → `transformAdvancedMobileSearch` (same criteria pattern)
- `jamfpro_enrollment_customization` → `transformEnrollmentCustomization` (top-level `enrollment_customization_image_source`→`icon_source`, `site_id` drop, `text_color`→`body_text_color`, pane blocks→lists with renames)
- `jamfpro_sso_settings` → `transformSSOSettings` (sub-blocks→object attrs, `enrollment_sso_config` drop)
- `jamfpro_computer_prestage_enrollment` → `transformComputerPrestage` (blocks→objects, WO before conversion, drop recovery_lock/prestage profile attrs)
- `jamfpro_mobile_device_prestage_enrollment` → `transformMobileDevicePrestage` (blocks→objects, `names {}` restructuring)

**Golden tests passing**: 33 test suites (run `go test ./migrate/ -run TestGolden -v` from `utils/jamformer-migrate/`).

## Key technical decisions already locked in

- `orderedAttrNames(body)` extracts attribute names in document order — essential for deterministic output
- `replaceStringLiteral()` handles string literal transforms
- `rewriteFileText()` handles cross-reference expression rewrites (`.id` → `.jamf_pro_id`) at text level
- `blockBodyToObjectLiteral()` uses `orderedAttrNames` for deterministic attribute order
- `applyAttrMappings` is called before `StructuralTransform` in `applyMapping`
- `transformAdvancedSearchCriteria` is SEPARATE from `transformCriteriaBlocks` — advanced searches keep `name`/`search_type` attr names; device groups rename them to `criteria`/`operator`
- `admin_password_wo_version` injection happens BEFORE `transformPrestageCommon` converts blocks to objects
- LDAP account block and mapping block attrs must use `orderedAttrNames` (not `range .Attributes()`)
- Inventory collection attr renames must use `orderedAttrNames` (not `range renames` map)

## File structure

```
utils/jamformer-migrate/
├── main.go
├── go.mod
├── migrate/
│   ├── mapping.go
│   ├── transform.go                 (~1550 lines)
│   ├── migrate.go
│   ├── report.go
│   ├── migrate_test.go
│   └── testdata/
│       ├── tier1_renames/
│       ├── script/
│       ├── api_client/
│       ├── smart_computer_group/
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
│       ├── app_installer/
│       ├── macos_config_profile/
│       ├── mobile_config_profile/
│       ├── policy/
│       ├── package/
│       ├── disk_encryption/
│       ├── account/
│       ├── account_group/
│       ├── ldap_server/
│       ├── restricted_software/
│       ├── inventory_collection/
│       ├── advanced_computer_search/
│       ├── advanced_mobile_search/
│       ├── enrollment_customization/
│       ├── sso_settings/
│       ├── computer_prestage/
│       └── mobile_prestage/
```

## Current test state

```
go test ./migrate/ -run TestGolden -v
```

All 33 test suites PASS. Run from `utils/jamformer-migrate/`.

## What needs to be done next

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
2. **`orderedAttrNames(body)`** must be used any time you iterate `body.Attributes()` or a block's attributes and order matters. `blockBodyToObjectLiteral` already does this. NEVER use `range body.Attributes()` when output order matters.
3. **String literal transforms** must use `replaceStringLiteral()` — not byte-level token manipulation.
4. **WriteOnly fields**: every resource with a password/secret must have `*_wo_version = 1` injected after the secret attr. Inject BEFORE block→object conversion.
5. **Golden files reflect actual hclwrite output** — `SetAttributeRaw` appends renamed attrs to the body end. Use `-update` to generate goldens from the engine, then verify correctness manually.
6. **`transformAdvancedSearchCriteria`** keeps `name`/`search_type` attr names (for advanced searches). **`transformCriteriaBlocks`** renames `name`→`criteria`, `search_type`→`operator` (for device groups only).
7. **`blockBodyToObjectLiteral`** serializes a body's attrs in document order. Use for all block→object conversions.
