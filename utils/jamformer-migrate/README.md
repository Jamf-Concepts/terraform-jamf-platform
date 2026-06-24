# jamformer-migrate

A CLI tool that migrates Terraform configuration files from the community
[`deploymenttheory/jamfpro`](https://registry.terraform.io/providers/deploymenttheory/jamfpro)
provider to the official
[`Jamf-Concepts/jamfplatform`](https://registry.terraform.io/providers/Jamf-Concepts/jamfplatform)
provider.

## Overview

`jamformer-migrate` reads every `.tf` file in your project directory, rewrites
`jamfpro_*` resources to their `jamfplatform_*` equivalents, and writes a
migration report telling you exactly what changed and what needs a manual look.
It uses a proper HCL AST parser — not regex — so comments, formatting, and
untouched resources are preserved with minimal diff noise.

## Prerequisites

- Go 1.21 or later (to build from source)
- Your Terraform project on a non-`main` / non-`master` branch

## Installation

```
git clone https://github.com/jamf/terraform-jamf-platform
cd terraform-jamf-platform/utils/jamformer-migrate
go build -o jamformer-migrate .
```

Place the resulting binary somewhere on your `$PATH`, or run it directly with
`go run .`.

## Usage

```
jamformer-migrate [flags] <input-dir>
```

`<input-dir>` is the directory containing your `.tf` files. The tool walks the
directory recursively and rewrites every file that contains a known `jamfpro_*`
resource type.

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | false | Print the migration report to stdout; do not write any files. |
| `--report <path>` | `<input-dir>/migration-report.md` | Path for the written report. |
| `--resources <types>` | all | Comma-separated list of source types to migrate, e.g. `jamfpro_policy,jamfpro_script`. |
| `--force` | false | Allow running on `main` or `master` branch. |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | All resources migrated cleanly — no manual work needed. |
| `1` | Migration complete, but one or more resources need manual review (check the report). |
| `2` | Fatal error — invalid input directory, parse failure, etc. |

## Typical migration workflow

### 1. Create a working branch

The tool refuses to run on `main` or `master` to protect you from accidental
commits directly to your main line.

```sh
git checkout -b migrate-to-jamfplatform
```

### 2. Preview what will change

```sh
jamformer-migrate --dry-run ./modules
```

The report is printed to stdout. Review which resources will be rewritten and
which need manual attention before anything is touched on disk.

### 3. Run the migration

```sh
jamformer-migrate ./modules
```

Files are rewritten in place. A `migration-report.md` is written to the input
directory.

### 4. Review the report

Open `migration-report.md`. Every resource is listed under one of three
outcomes:

- **✓ Migrated cleanly** — no further action needed.
- **⚠ Manual review** — the tool made a best-effort rewrite but flagged
  something that requires your attention. The report explains why and
  what to do.
- **✗ Skipped** — the resource type has no equivalent in the new provider.
  The original block is left untouched; the report says why.

### 5. Fix up manual review items

Common review items and what to do about them:

| Resource | Flag | Action |
|----------|------|--------|
| Any resource with a password | `*_wo_version = 1` injected | The new provider uses WriteOnly secrets. `*_wo_version` starts at `1`; bump the integer to rotate the secret on the next apply. |
| `jamfpro_jamf_connect` | `config_profile_uuid` → `profile_id` | `profile_id` is now a numeric Jamf Pro ID, not a UUID. Replace the value. |
| `jamfpro_local_admin_password_settings` | Rotation interval attrs | Values changed from integer seconds to duration strings (e.g. `86400` → `"1 day"`). Update manually. |
| `jamfpro_policy` | `date_time_limitations` / `network_limitations` removed | These blocks have no equivalent. Reconfigure scheduling in the Jamf Pro UI if needed. |
| `jamfpro_account` | `jss_settings_privileges` / `casper_admin_privileges` dropped | No equivalents in the new schema. Verify the privilege set is complete. |
| Static device groups | `members` values unchanged | The new provider uses device UDIDs, not numeric Jamf Pro IDs. Replace member values with UDIDs from the Jamf Pro API. |
| `jamfpro_ldap_server` | Entire resource restructured | LDAP config is security-sensitive. Review all `connection_settings` and `mappings_for_users` sub-attributes carefully. |

### 6. Update provider and state references

After the `.tf` files are rewritten, update your provider block:

```hcl
terraform {
  required_providers {
    jamfplatform = {
      source  = "Jamf-Concepts/jamfplatform"
      version = "~> 1.0"
    }
  }
}
```

Remove the old `deploymenttheory/jamfpro` provider entry. Then run:

```sh
terraform init -upgrade
terraform plan
```

Address any remaining plan errors before applying.

## Resource coverage

The tool handles all resource types from the `deploymenttheory/jamfpro`
provider that have an equivalent in `Jamf-Concepts/jamfplatform`. Resources
are grouped into four internal tiers based on migration complexity:

- **Tier 1** — type rename only (7 resources)
- **Tier 2** — attribute renames / drops (25+ resources)
- **Tier 3** — structural rewrites, block-to-object conversions (17 resources)
- **Tier 4** — many-to-one folding: all six smart/static computer/mobile group types → `jamfplatform_device_group`

A small number of resource types have no equivalent in the new provider
(e.g. `jamfpro_engage_settings`) and are left in place with a report entry.

## Limitations

- **State management** — the tool rewrites `.tf` source files only. It does
  not generate `terraform import` blocks or `removed` blocks. You will need to
  manage state migration separately (typically by importing resources into the
  new provider's state).
- **Expression values** — rotation interval duration strings
  (`password_rotation_time_seconds` → `rotation_interval`) cannot be converted
  automatically. The value is renamed but left as-is with a review flag.
- **Registry modules** — remote module sources are not traversed. Run the tool
  against local module directories individually.
