# terraform-jamf-platform — `ref-jamfpro` reference layout

> **You are on the `ref-jamfpro` branch.** This is an orphaned reference
> branch containing a single-module Terraform layout for Jamf Pro and Jamf
> Platform, intended for admins new to Terraform and for Pro Services
> technical enablement engagements. Other branches in this repository are
> unrelated and follow different layouts.

Terraform configuration for managing Jamf Pro and Jamf Platform using the
[deploymenttheory/jamfpro](https://registry.terraform.io/providers/deploymenttheory/jamfpro/latest)
and [Jamf-Concepts/jamfplatform](https://registry.terraform.io/providers/Jamf-Concepts/jamfplatform/latest)
providers.

This repository is aimed at Jamf administrators who are new to Terraform. It
assumes strong familiarity with Jamf Pro — policies, smart groups, configuration
profiles, ADE, VPP — and explains the Terraform-specific concepts as they come
up. It is not a general Terraform tutorial.

Jamf publishes and maintains these providers. We do not deliver Infrastructure
as Code transformation as a commercial service. This repository is a reference
and learning resource; it is not a deliverable.

---

## What this covers

- Jamf Pro: categories, departments, buildings, smart groups, configuration
  profiles, packages, policies, app installers, Mac and iOS applications,
  ADE device enrollments, VPP, computer and mobile device prestages
- Jamf Platform: Blueprints, Compliance Benchmarks

---

## Prerequisites

- A Jamf Pro sandbox tenant — **do not use a production instance while learning**
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.11.0
- A Jamf Platform integration (optional — Platform resources are skipped if
  credentials are not supplied)
- OAuth2 API client credentials for each provider (see setup steps below)

### Installing Terraform

On macOS, the recommended approach is Homebrew:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform -version
```

For other platforms, see [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install).

### Recommended editor

[Visual Studio Code](https://code.visualstudio.com) with the
[HashiCorp Terraform extension](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform)
gives you syntax highlighting, auto-complete, and inline documentation for
resource attributes. It is not required but makes editing `.tf` files
significantly easier.

### Jamf Pro: create an API client

1. In Jamf Pro, go to **Settings > System > API roles and clients**.
2. Create an API Role with the privileges required. Use **All** while learning;
   tighten later.
3. Create an API Client, attach the role, and generate a secret.
4. Note the **Client ID** and **Client Secret** — these go in `terraform.tfvars`.

### Jamf Platform: create an integration

See [Getting started with the Platform API](https://developer.jamf.com/platform-api/reference/getting-started-with-platform-api)
for full instructions. In short:

1. Sign in to [account.jamf.com](https://account.jamf.com), enroll in the
   Platform API Gateway Beta via **Feedback Program**.
2. Go to **Integrations** and create a new integration. Select your region and
   the Jamf Pro tenant(s) to scope, and assign the required permissions.
3. Copy the **client ID**, **client secret**, and **tenant ID** from the
   Integration details panel. The secret is shown only once.
4. Your `base_url` is the regional API gateway endpoint:
   `https://us.apigw.jamf.com`, `https://eu.apigw.jamf.com`, or
   `https://apac.apigw.jamf.com`.

---

## Repository structure

```
terraform-jamf-platform/
├── environments/
│   └── dev/                          # Environment-specific wiring
│       ├── backend.tf                # State backend (local by default)
│       ├── provider.tf               # Provider config + credentials
│       ├── variables.tf              # Variable declarations
│       ├── terraform.tfvars.example  # Credential template
│       ├── main.tf                   # Calls modules/jamfpro
│       └── support_files/
│           ├── device_enrollment_tokens/   # .p7m token files (gitignored)
│           └── volume_purchasing_tokens/   # .vpptoken files (gitignored)
└── modules/
    └── jamfpro/                      # Canonical Jamf resource definitions
        ├── terraform.tf
        ├── variables.tf
        ├── buildings.tf
        ├── categories.tf
        ├── departments.tf
        ├── device_enrollments.tf
        ├── volume_purchasing_locations.tf
        ├── smart_computer_groups.tf
        ├── smart_mobile_device_groups.tf
        ├── macos_configuration_profiles.tf
        ├── mobile_device_configuration_profiles.tf
        ├── computer_prestages.tf
        ├── mobile_device_prestage_enrollments.tf
        ├── packages.tf
        ├── policies.tf
        ├── app_installers.tf
        ├── mac_applications.tf
        ├── mobile_device_applications.tf
        ├── blueprints.tf
        ├── compliance_benchmarks.tf
        └── support_files/
            ├── macos_configuration_profiles/
            ├── mobile_device_configuration_profiles/
            └── app_configurations/
```

**`environments/dev/`** contains only what differs per environment: state
backend config, provider URLs, and credentials. It calls `modules/jamfpro`
to deploy the shared resource definitions.

**`modules/jamfpro/`** contains the actual Jamf resource definitions — the
policies, profiles, groups, and so on. This is where most editing happens.
Profile payloads and app configurations live in `support_files/` alongside
the resources that reference them.

### Why this split

The same architecture handles a single sandbox instance and a fleet of
production environments without restructuring:

- **One canonical source of resource definitions.** All policies, profiles,
  smart groups, and so on live in `modules/jamfpro/`. There is no copy of
  the policy library in each environment folder, so a fix or new resource
  is written once and inherited by every environment.
- **One env folder per Jamf tenant.** Each environment folder holds only
  what is genuinely tenant-specific: which Jamf Pro URL to talk to, which
  OAuth2 credentials to use, where state lives, and which Apple-issued
  tokens to read. Everything else comes from the module.
- **Per-environment state isolation.** Each env folder has its own
  `terraform.tfstate`, so applying to dev cannot affect prod and vice
  versa. Concurrent applies against different tenants are safe.
- **Two ways to handle environment-specific differences.** Resources that
  are common but configured slightly differently (e.g. a smart group with
  different criteria in dev vs prod) become module variables, set per-env
  in `terraform.tfvars`. Resources that should exist in only one
  environment (e.g. a debug-only smart group in dev) are defined directly
  in that environment's `main.tf` alongside the module call.

### How it scales

| Stage | Layout |
|---|---|
| Day 1 — single sandbox tenant | `environments/dev/` only. Module is shared but only one env consumes it. |
| Day N — sandbox plus production | Copy `environments/dev/` to `environments/production/`. Update the new folder's `terraform.tfvars` and (if using a remote backend) `backend.tf`. Both env folders call the same module. |
| Day N+1 — add staging or another business unit | Repeat the copy. Each new env is one folder, one state file, one set of credentials. The module never changes shape. |

Shared changes go in `modules/jamfpro/` and apply to every environment on
its next plan. Environment-only changes go in that environment's folder.
This is the boundary that lets the repo grow from one tenant to many
without rewriting anything.

---

## Getting started

### 1. Clone and configure credentials

This work lives on the orphaned `ref-jamfpro` branch and will not move.
Other branches in this repository are unrelated. Use `--branch` and
`--single-branch` so you only fetch what you need:

```bash
git clone --branch ref-jamfpro --single-branch https://github.com/Jamf-Concepts/terraform-jamf-platform.git
cd terraform-jamf-platform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your tenant URL and OAuth2 credentials. This file
is gitignored and must never be committed.

Alternatively, export credentials as environment variables — no `terraform.tfvars`
file needed:

```bash
export TF_VAR_jamfpro_instance_fqdn="https://yourcompany.jamfcloud.com"
export TF_VAR_jamfpro_client_id="..."
export TF_VAR_jamfpro_client_secret="..."
```

### 2. Initialise Terraform

```bash
cd environments/dev
terraform init
```

This downloads the required providers into a local `.terraform/` cache.
Run it once after cloning. To update providers to newer versions within the
declared constraints, run `terraform init -upgrade` instead.

### 3. Format and validate

`terraform fmt -recursive` reformats every `.tf` file under the given path
to canonical style. Run it from the repo root after edits. `terraform validate`
checks for syntax errors and broken references in the environment you are
about to plan against.

```bash
# From the repo root
terraform fmt -recursive

# From environments/dev
terraform validate
```

### 4. Plan

```bash
terraform plan -parallelism=1
```

`-parallelism=1` is required. The Jamf Pro API rate-limits concurrent
requests and returns errors under parallel load. Always run plan and apply
single-threaded.

Terraform will show every resource it intends to create. Review it before
applying. A resource with `+` will be created; `-` destroyed; `~` modified
in place.

### 5. Apply

```bash
terraform apply -parallelism=1
```

Type `yes` when prompted. Terraform creates each resource in your Jamf Pro
tenant and records the result in the state file (`terraform.tfstate`).

The state file is Terraform's record of everything it has created. Do not
delete or edit it manually — if it is lost, Terraform can no longer manage
those resources without re-importing them. The [Graduating to remote state](#graduating-to-remote-state)
section covers how to store state somewhere more durable when you are ready.

### 6. Removing resources

To remove everything Terraform has created in your tenant:

```bash
terraform destroy -parallelism=1
```

This is useful for cleaning up a sandbox after testing. It will permanently
delete every resource in the state file from your Jamf tenant.

---

## Apple-issued tokens (ADE and VPP)

ADE server tokens (`.p7m`) and VPP service tokens (`.vpptoken`) are
downloaded from Apple Business Manager or Apple School Manager. They are
tenant-specific — each Jamf Pro environment has its own.

Place token files in the appropriate directory under your environment folder:

```
environments/dev/support_files/device_enrollment_tokens/your-ade-token.p7m
environments/dev/support_files/volume_purchasing_tokens/your-vpp-token.vpptoken
```

`*.p7m` and `*.vpptoken` are gitignored in this repository to prevent
accidental exposure when cloning or forking. In your own private repo you
have three handling options:

- **Commit the tokens to a private repo** — simplest pattern for small teams
  and the most realistic for customers without an existing secret manager.
  Remove `*.p7m` and `*.vpptoken` from `.gitignore` and trust the repo's
  access controls. Rotate by replacing the file and committing.
- **Encrypt at rest in the repo** — SOPS with age, git-crypt, or sealed
  secrets. Tokens commit as ciphertext and decrypt at apply time. Defense in
  depth at the cost of an extra tool to manage.
- **Externalise via a secret store** — fetch tokens at apply time from Vault,
  AWS Secrets Manager, GCP Secret Manager, or your CI's secret store. Most
  secure, most plumbing. The CI runner writes the file to disk before
  `terraform apply` runs.

Whichever you pick, rotate tokens on Apple's published schedule and revoke
any token that may have been exposed.

To enable ADE and VPP resources, set the token path variables in
`terraform.tfvars`:

```hcl
ade_token_path_default = "support_files/device_enrollment_tokens/your-ade-token.p7m"
vpp_token_path_default = "support_files/volume_purchasing_tokens/your-vpp-token.vpptoken"
```

The root module reads each file and passes the encoded content to
`modules/jamfpro`. The module never sees the file path — only the content.

---

## Customising the module

**Adding a new policy, profile, or smart group:** edit the relevant `.tf`
file in `modules/jamfpro/` directly. Resources follow the `for_each`-over-locals
pattern where there are multiple similar items, or single resource blocks where
configuration is unique. Follow whichever pattern the surrounding file uses.

**Adding a configuration profile payload:** place the `.mobileconfig` file in
`modules/jamfpro/support_files/macos_configuration_profiles/` (or the
mobile equivalent), then reference it in the resource with:

```hcl
payloads = file("${path.module}/support_files/macos_configuration_profiles/your-profile.mobileconfig")
```

`${path.module}` always resolves to the `modules/jamfpro/` directory, regardless
of where Terraform is invoked from.

**Blueprints and `deployed = false`:** Blueprints in `blueprints.tf` are
created with `deployed = false`, which means Jamf Platform creates the
Blueprint record but does not push its settings to devices. This is intentional
for a reference configuration — review the Blueprint in the UI and set
`deployed = true` when ready to enforce the settings in your environment.

**Changing scope or behaviour per environment:** if a resource needs different
values in dev vs production (a different smart group scope, a different policy
frequency), expose it as a module variable in `modules/jamfpro/variables.tf`,
wire it through in `environments/dev/main.tf`, and set the value in
`terraform.tfvars`. For resources that should exist only in a specific
environment, define them directly in `environments/dev/main.tf` rather than
in the shared module.

---

## Adding an environment

To add a production environment:

```bash
cp -r environments/dev environments/production
```

Edit the files that differ per environment:

| File | What to change |
|---|---|
| `backend.tf` | If using a remote backend, update the state key, prefix, or workspace name to be unique per environment (e.g. `jamf/production/terraform.tfstate`). With the default local backend, no change is needed — each env folder gets its own `terraform.tfstate`. |
| `provider.tf` | No change needed if both tenants are on the same region; the URLs come from `terraform.tfvars`. |
| `terraform.tfvars` | Credentials and token paths for the production tenant. |

Run `terraform init` from the new environment folder before the first plan.

### Long-lived branch strategy (optional, customer-side)

This repository is structured around env-folders, not Git branches. The
notes below are a separate pattern you can adopt in **your own** Git repo
once you have copied this project out and started managing your own tenants.
It is not how this repo itself is laid out.

A common branch-based promotion model:

- `main` — production environment
- `staging` — branched from main, staging environment
- `dev` — branched from staging, sandbox/dev environment
- Feature branches off `dev` for individual changes

Changes are promoted by merging dev into staging (reviewed), then staging
into main (reviewed). `backend.tf` is the one file that may legitimately
diverge between branches (different state keys per environment) and should
not be merged across environment boundaries. `terraform.tfvars` is
gitignored and configured locally on each checkout, so it never enters the
merge picture at all.

This is the approach used by [Deployment Theory's demo repository](https://github.com/deploymenttheory/terraform-demo-jamfpro)
and is documented there in more detail. Whether to use folders, branches,
or both is a customer decision — Jamf does not prescribe one over the other.

---

## Graduating to remote state

Local state (the default) is fine for a single operator on a single machine.
When more than one person applies changes, or when you want state locked during
apply to prevent concurrent runs, switch to a remote backend.

The four most common options are documented as commented examples in
`environments/dev/backend.tf`. Uncomment exactly one, fill in the values for
your account, and run:

```bash
terraform init -migrate-state
```

Terraform will copy your local state into the new backend.

**HCP Terraform** is the lowest-friction remote option for teams without
existing cloud infrastructure. The free tier covers up to 500 managed
resources. Create one workspace per environment, point each workspace's
Working Directory at the relevant `environments/<name>/` folder, and HCP
Terraform handles locking, history, and remote runs.

Jamf does not provide guidance on architecting remote state, CI/CD pipelines,
or workspace strategy beyond what is documented here. If you need that help,
consult your existing IaC tooling vendor or a partner.

---

## Relationship to jamformer

[jamformer](https://github.com/Jamf-Concepts/jamformer) is a tool that reads
an existing Jamf Pro instance and generates Terraform configuration files from
it. It produces a single-environment flat output in a structure similar to
`modules/jamfpro/` in this repository.

This repository is what you refactor a jamformer export into once you need
more than one environment. The file naming conventions (`smart_computer_groups.tf`,
`macos_configuration_profiles.tf`, etc.) and the support files layout
(`support_files/macos_configuration_profiles/`, etc.) are intentionally
aligned with jamformer's output so the refactor is a move rather than a rewrite.

### Token convention

jamformer reads token files directly inside the resource via `file()`. This
repository reads token files in `environments/dev/main.tf` and passes the
content into the module instead, because module boundaries should not expose
filesystem paths from the calling environment. Two transforms are used:

- **ADE** — `ade_token_encoded_default = filebase64(var.ade_token_path_default)`. The
  deploymenttheory provider expects base64-encoded `.p7m` content.
- **VPP** — `vpp_token_default = trimspace(file(var.vpp_token_path_default))`.
  Raw `.vpptoken` content, no encoding.

If you are refactoring a jamformer export into this layout, replace the
in-resource `file()` calls with these module variables and move the actual
file reads up to `environments/dev/main.tf`.

### Import blocks

jamformer generates `import` blocks at the root of its output, targeting
resources by their root-level address:

```hcl
import {
  to = jamfpro_smart_computer_group_v2.example
  id = "123"
}
```

In this repository the same resource lives inside the `jamfpro` module, so
its address is `module.jamfpro.jamfpro_smart_computer_group_v2.example`. You
have two options for adopting a jamformer export here:

1. **Rewrite the imports** — move each `import` block to `environments/dev/main.tf`
   and prefix every `to` address with `module.jamfpro.`. Terraform 1.5+
   supports module-pathed import targets.
2. **Apply flat first, then relocate** — apply the jamformer output as-is
   against your tenant in a flat single-env scaffold, then use
   `terraform state mv` to move each resource into the module address. The
   import blocks can be deleted once state is in place.

Option 2 is generally easier for large jamformer exports because you skip
the find-and-replace step and let Terraform manage the state rewrite.

---

## Provider versions

| Provider | Source | Minimum version |
|---|---|---|
| jamfpro | `deploymenttheory/jamfpro` | 0.37.0 |
| jamfplatform | `Jamf-Concepts/jamfplatform` | 0.16.3 |
| time | `hashicorp/time` | 0.13.0 |
| itunessearchapi | `neilmartin83/itunessearchapi` | 0.1.0 |

The `itunessearchapi` provider is a community-maintained provider, not a Jamf
product. It is used to fetch app metadata (name, version, bundle ID, icon URL)
from the iTunes Search API at plan time, removing the need to pin those values
manually. It is not required for any Jamf Pro or Jamf Platform functionality
and can be removed along with `mac_applications.tf` and
`mobile_device_applications.tf` if preferred.

Provider version constraints are declared in `modules/jamfpro/terraform.tf`.
Run `terraform init -upgrade` to update to newer versions within the
constraints.

---

## Troubleshooting

**`Error: 429 Too Many Requests`** — the Jamf Pro API is rate-limiting you
even with `-parallelism=1`. The provider retries internally but occasionally
surfaces the error. Re-run `terraform apply` and it usually resolves.

**`Error: invalid OAuth2 token` mid-apply** — the access token expired
during a long-running apply. The provider refreshes automatically but
timing edge cases exist. Re-run `terraform apply`; Terraform picks up where
it left off using state.

**`Error: encoded_token is invalid`** on the device enrollment resource —
the `.p7m` file is being passed as raw content instead of base64. Confirm
`environments/dev/main.tf` uses `filebase64()` for the ADE token, not
`file()`.

**Postcondition failed on volume_purchasing_locations** — the async VPP
content sync did not complete in 2 minutes. Open the VPP location in Jamf
Pro and wait for the content list to populate, then re-run `terraform apply`.

**`Error: state locked`** — a previous run crashed without releasing the
state lock. The error message includes a lock ID. Run
`terraform force-unlock <ID>` to clear it. Only do this if you are sure
no other apply is in progress.

**`terraform plan` shows changes you did not make** — someone has edited a
resource in the Jamf Pro UI. Either revert the manual change in the UI or
update the HCL to match. Resources should be managed in one place, not
both.

**Different provider versions on different machines** — the
`.terraform.lock.hcl` is gitignored in this repository (see [CONTRIBUTING.md](CONTRIBUTING.md)
for the rationale). Run `terraform init -upgrade` on each machine to align
on the latest version that satisfies the constraints in `terraform.tf`.

---

## Further reading

- [Resources for getting started with Terraform and Jamf](https://concepts.jamf.com/guides/infrastructure-as-code/resources-for-getting-started-with-terraform-and-jamf/) — curated learning resources for Jamf admins new to IaC
- [Managing Jamf configuration with Terraform: an introduction](https://concepts.jamf.com/guides/infrastructure-as-code/managing-jamf-configuration-with-terraform-an-introduction/) — hands-on walkthrough using the Jamf Pro provider
- [Managing the Jamf Platform with Terraform](https://concepts.jamf.com/guides/infrastructure-as-code/managing-the-jamf-platform-with-terraform-the-jamf-platform-provider/) — Jamf Platform provider deep-dive
- [Adopting Terraform for Jamf with jamformer](https://concepts.jamf.com/guides/infrastructure-as-code/adopting-terraform-for-jamf-with-jamformer/) — using jamformer to bootstrap from an existing tenant
