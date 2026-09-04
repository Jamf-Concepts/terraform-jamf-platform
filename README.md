# terraform-jamf-platform: `ref-jamfplatform` reference layout

> **You are on the `ref-jamfplatform` branch.** This is an orphaned reference
> branch containing a multi-environment Terraform layout for the **Jamf
> Platform** provider, intended for admins new to Terraform and for Pro
> Services technical enablement engagements. Other branches in this
> repository are unrelated and follow different layouts.

Terraform configuration for managing the Jamf Platform using the
[Jamf-Concepts/jamfplatform](https://registry.terraform.io/providers/Jamf-Concepts/jamfplatform/latest)
provider, Jamf's own provider, which fronts both Jamf Pro resources and
Jamf Platform features such as Blueprints through a single regional API
gateway.

This repository is aimed at Jamf administrators who are new to Terraform. It
assumes strong familiarity with Jamf (policies, smart groups, configuration
profiles, ADE, VPP) and explains the Terraform-specific concepts as they come
up. It is not a general Terraform tutorial.

Jamf publishes and maintains this provider. We do not deliver Infrastructure
as Code transformation as a commercial service. This repository is a reference
and learning resource; it is not a deliverable.

---

## What this covers

- Jamf Pro resources (via the `jamfplatform` provider): categories,
  departments, buildings, device groups, configuration profiles, packages,
  policies, app installers, Mac App Store and mobile device apps, icons,
  ADE device enrollments, VPP, computer and mobile device prestages
- Jamf Platform features: **Blueprints** (software update enforcement)

---

## Prerequisites

- A Jamf sandbox tenant. **Do not use a production instance while learning**
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.14.0
- An API integration in your Jamf Account for the Jamf Platform provider
  (see setup steps below)

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
resource attributes. It is optional, and editing `.tf` files is harder without
it.

### Jamf Platform: create an API integration

The Jamf Platform provider authenticates through a regional API gateway using
an API integration created in your Jamf Account, not in the Jamf Pro UI.

1. Sign in to [account.jamf.com](https://account.jamf.com) and open
   **Integrations**.
2. Create an integration and scope it to the **platform environment** holding
   your tenant. A platform environment groups tenants across product types,
   and Jamf Account offers the Blueprints permissions at no other scope.
3. Grant the permissions the module needs. The picker groups them by category
   with a checkbox per action. Use broad access while learning and tighten
   later.
4. Generate a **Client ID** and **Client Secret** for the integration.
5. Note the **Environment ID**, shown in the integration details panel at
   account.jamf.com.
6. Pick the **API gateway URL** for your region:
   - US: `https://us.api.jamfcloud.com`
   - EU: `https://eu.api.jamfcloud.com`
   - APAC: `https://apac.api.jamfcloud.com`

The Client ID, Client Secret, Environment ID, and base URL go in
`terraform.tfvars`.

---

## Repository structure

```
terraform-jamf-platform/
├── environments/
│   └── dev/                          # Environment-specific wiring
│       ├── backend.tf                # State backend (local by default)
│       ├── terraform.tf              # Root provider requirements/versions
│       ├── provider.tf               # Provider config + credentials
│       ├── variables.tf              # Variable declarations
│       ├── terraform.tfvars.example  # Credential template
│       ├── main.tf                   # Calls modules/jamfplatform
│       └── support_files/
│           ├── device_enrollment_tokens/   # .p7m token files (gitignored)
│           └── volume_purchasing_tokens/   # .vpptoken files (gitignored)
└── modules/
    └── jamfplatform/                 # Canonical Jamf resource definitions
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
        ├── mac_app_store_apps.tf
        ├── mobile_device_apps.tf
        ├── blueprints.tf
        └── support_files/
            ├── macos_configuration_profiles/
            ├── mobile_device_configuration_profiles/
            └── app_configurations/
```

**`environments/dev/`** contains only what differs per environment: state
backend config, provider URLs, and credentials. It calls
`modules/jamfplatform` to deploy the shared resource definitions.

**`modules/jamfplatform/`** contains the Jamf resource definitions:
the policies, profiles, groups, blueprints, and so on. This is where most
editing happens. Profile payloads and app configurations live in
`support_files/` alongside the resources that reference them.

### Why this split

The same architecture handles a single sandbox instance and a fleet of
production environments without restructuring:

- **One canonical source of resource definitions.** All policies, profiles,
  device groups, and so on live in `modules/jamfplatform/`. There is no copy
  of the policy library in each environment folder, so a fix or new resource
  you write once and every environment inherits.
- **One env folder per Jamf tenant.** Each environment folder holds only
  what is tenant-specific: which API gateway to talk to, which
  integration credentials and environment ID to use, where state lives, and which
  Apple-issued tokens to read. Everything else comes from the module.
- **Per-environment state isolation.** Each env folder has its own
  `terraform.tfstate`, so applying to dev cannot affect prod and vice
  versa. Concurrent applies against different tenants are safe.
- **Two ways to handle environment-specific differences.** Resources that
  are common but configured a little differently (e.g. a device group with
  different criteria in dev vs prod) become module variables, set per-env
  in `terraform.tfvars`. Resources that should exist in only one
  environment (e.g. a debug-only device group in dev) go in that
  environment's `main.tf` alongside the module call.

### How it scales

| Stage | Layout |
|---|---|
| Day 1: single sandbox tenant | `environments/dev/` only. Module is shared but only one env consumes it. |
| Day N: sandbox plus production | Copy `environments/dev/` to `environments/production/`. Update the new folder's `terraform.tfvars` and (if using a remote backend) `backend.tf`. Both env folders call the same module. |
| Day N+1: add staging or another business unit | Repeat the copy. Each new env is one folder, one state file, one set of credentials. The module never changes shape. |

Shared changes go in `modules/jamfplatform/` and apply to every environment
on its next plan. Environment-only changes go in that environment's folder.
This is the boundary that lets the repo grow from one tenant to many
without rewriting anything.

---

## Getting started

### 1. Clone and configure credentials

This work lives on the orphaned `ref-jamfplatform` branch and will not move.
Other branches in this repository are unrelated. Use `--branch` and
`--single-branch` so you only fetch what you need:

```bash
git clone --branch ref-jamfplatform --single-branch https://github.com/Jamf-Concepts/terraform-jamf-platform.git
cd terraform-jamf-platform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your regional API gateway URL, integration
credentials, and environment ID. This file is gitignored and must never be
committed.

Or export credentials as environment variables, with no `terraform.tfvars`
file needed:

```bash
export TF_VAR_jamfplatform_base_url="https://us.api.jamfcloud.com"
export TF_VAR_jamfplatform_client_id="..."
export TF_VAR_jamfplatform_client_secret="..."
export TF_VAR_jamfplatform_environment_id="..."
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

`-parallelism=1` matters. The Jamf API rate-limits concurrent
requests and returns errors under parallel load. Always run plan and apply
single-threaded.

Terraform will show every resource it intends to create. Review it before
applying. A resource with `+` will be created; `-` destroyed; `~` modified
in place.

### 5. Apply

```bash
terraform apply -parallelism=1
```

Type `yes` when prompted. Terraform creates each resource in your Jamf
tenant and records the result in the state file (`terraform.tfstate`).

The state file is Terraform's record of everything it has created. Do not
delete or edit it by hand. Lose it and Terraform can no longer manage
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
tenant-specific, because each Jamf environment has its own.

Place token files in the appropriate directory under your environment folder:

```
environments/dev/support_files/device_enrollment_tokens/your-ade-token.p7m
environments/dev/support_files/volume_purchasing_tokens/your-vpp-token.vpptoken
```

`*.p7m` and `*.vpptoken` are gitignored in this repository to prevent
accidental exposure when cloning or forking. In your own private repo you
have three handling options:

- **Commit the tokens to a private repo.** Simplest pattern for small teams
  and the most realistic for customers without an existing secret manager.
  Remove `*.p7m` and `*.vpptoken` from `.gitignore` and trust the repo's
  access controls. Rotate by replacing the file and committing.
- **Encrypt at rest in the repo.** SOPS with age, git-crypt, or sealed
  secrets. Tokens commit as ciphertext and decrypt at apply time. Defense in
  depth at the cost of an extra tool to manage.
- **Externalise via a secret store.** Fetch tokens at apply time from Vault,
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
`modules/jamfplatform`. The module sees the content, never the file path.

---

## Customising the module

**Adding a new policy, profile, or device group:** edit the relevant `.tf`
file in `modules/jamfplatform/`. Resources follow the `for_each`-over-locals
pattern where there are multiple similar items, or single resource blocks where
configuration is unique. Follow whichever pattern the surrounding file uses.

**Adding a configuration profile payload:** place the `.mobileconfig` file in
`modules/jamfplatform/support_files/macos_configuration_profiles/` (or the
mobile equivalent), then reference it in the resource with:

```hcl
payloads = file("${path.module}/support_files/macos_configuration_profiles/your-profile.mobileconfig")
```

`${path.module}` always resolves to the `modules/jamfplatform/` directory, regardless
of where Terraform is invoked from.

**Changing scope or behaviour per environment:** if a resource needs different
values in dev vs production (a different device group scope, a different policy
frequency), expose it as a module variable in `modules/jamfplatform/variables.tf`,
wire it through in `environments/dev/main.tf`, and set the value in
`terraform.tfvars`. For resources that should exist only in a specific
environment, declare them in `environments/dev/main.tf` rather than
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
| `backend.tf` | If using a remote backend, update the state key, prefix, or workspace name to be unique per environment (e.g. `jamf/production/terraform.tfstate`). With the default local backend, no change is needed, because each env folder gets its own `terraform.tfstate`. |
| `provider.tf` | No change needed if both tenants are in the same region; the gateway URL, credentials, and environment ID come from `terraform.tfvars`. |
| `terraform.tfvars` | Gateway URL, integration credentials, environment ID, and token paths for the production tenant. |

Run `terraform init` from the new environment folder before the first plan.

### Long-lived branch strategy (optional, customer-side)

This repository is structured around env-folders, not Git branches. The
notes below are a separate pattern you can adopt in **your own** Git repo
once you have copied this project out and started managing your own tenants.
It is not how this repo itself is laid out.

A common branch-based promotion model:

- `main`: production environment
- `staging`: branched from main, staging environment
- `dev`: branched from staging, sandbox/dev environment
- Feature branches off `dev` for individual changes

Changes are promoted by merging dev into staging (reviewed), then staging
into main (reviewed). `backend.tf` is the one file that may legitimately
diverge between branches (different state keys per environment) and should
not be merged across environment boundaries. `terraform.tfvars` is
gitignored and configured locally on each checkout, so it never enters the
merge picture at all.

Whether to use folders, branches, or both is a customer decision. Jamf does
not prescribe one over the other.

---

## Graduating to remote state

Local state (the default) is fine for a single operator on a single machine.
Once more than one person applies changes, or you want state locked during
apply to prevent concurrent runs, switch to a remote backend.

The most common options are documented as commented examples in
`environments/dev/backend.tf`. Uncomment one, fill in the values for
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
`modules/jamfplatform/` in this repository.

This repository is what you refactor a jamformer export into once you need
more than one environment. The file naming conventions
(`smart_computer_groups.tf`, `macos_configuration_profiles.tf`, etc.) and the
support files layout (`support_files/macos_configuration_profiles/`, etc.) are
aligned with jamformer's output on purpose, so the structural refactor is a
move rather than a rewrite.

> **Provider note.** Jamformer targets the `deploymenttheory/jamfpro`
> provider, whereas this branch uses the `Jamf-Concepts/jamfplatform`
> provider. The resource *type names* differ accordingly (`jamfpro_*` →
> `jamfplatform_pro_*`, smart groups → `jamfplatform_device_group`), so
> adopting a jamformer export here involves translating resource types in
> addition to moving files. The layout still lines up; the HCL bodies need
> provider-specific adjustment.

### Token convention

jamformer reads token files inside the resource via `file()`. This
repository reads token files in `environments/dev/main.tf` and passes the
content into the module instead, because module boundaries should not expose
filesystem paths from the calling environment. Apply two transforms:

- **ADE.** `ade_token_encoded_default = filebase64(var.ade_token_path_default)`.
  The provider expects base64-encoded `.p7m` content.
- **VPP.** `vpp_token_default = file(var.vpp_token_path_default)`.
  Raw `.vpptoken` content, no encoding.

If you are refactoring a jamformer export into this layout, replace the
in-resource `file()` calls with these module variables and move the actual
file reads up to `environments/dev/main.tf`.

### Import blocks

jamformer generates `import` blocks at the root of its output, targeting
resources by their root-level address. In this repository the same resource
lives inside the `jamfplatform` module, so its address is prefixed with
`module.jamfplatform.`:

```hcl
import {
  to = module.jamfplatform.jamfplatform_device_group.example
  id = "123"
}
```

You have two options for adopting a jamformer export here:

1. **Rewrite the imports.** Move each `import` block to `environments/dev/main.tf`
   and prefix every `to` address with `module.jamfplatform.`. Terraform 1.5+
   supports module-pathed import targets.
2. **Apply flat first, then relocate.** Apply the export as-is against your
   tenant in a flat single-env scaffold, then use `terraform state mv` to
   move each resource into the module address. The import blocks can be
   deleted once state is in place.

Option 2 is easier for large exports because you skip the
find-and-replace step and let Terraform manage the state rewrite.

---

## Provider versions

| Provider | Source | Minimum version |
|---|---|---|
| jamfplatform | `Jamf-Concepts/jamfplatform` | 0.29.0 |
| time | `hashicorp/time` | 0.13.0 |
| itunessearchapi | `neilmartin83/itunessearchapi` | 0.1.0 |

The `jamfplatform` provider is published and maintained by Jamf. It
authenticates through a regional API gateway using an API integration created
in your Jamf Account (see [Prerequisites](#prerequisites)) and exposes both
Jamf Pro resources (`jamfplatform_pro_*`) and Jamf Platform features such as
Blueprints (`jamfplatform_blueprints_blueprint`).

The `itunessearchapi` provider is a community-maintained provider, not a Jamf
product. It fetches app metadata (name, version, bundle ID, icon URL)
from the iTunes Search API at plan time, so you never pin those values by
hand. No Jamf functionality depends on it, and you can remove it
along with `mac_app_store_apps.tf` and `mobile_device_apps.tf` if preferred.

`modules/jamfplatform/terraform.tf` declares the provider version constraints,
and `environments/dev/terraform.tf` does the same for the root module. Run
`terraform init -upgrade` to update to newer versions within the constraints.

---

## Troubleshooting

**`Error: 429 Too Many Requests`.** The Jamf API is rate-limiting you
even with `-parallelism=1`. The provider retries internally but occasionally
surfaces the error. Re-run `terraform apply` and it usually resolves.

**`Error: invalid OAuth2 token` mid-apply.** The access token expired
during a long-running apply. The provider refreshes the token on its own, but
timing edge cases exist. Re-run `terraform apply` and Terraform picks up where
it left off from state.

**Authentication failures on `terraform plan`.** Confirm the `base_url`
matches your tenant's region (US/EU/APAC), and that the `client_id`,
`client_secret`, and `environment_id` belong to the same Jamf Account
integration. An environment ID from a different region will fail against the
wrong gateway.

**`Error: 403 OWNERSHIP_FORBIDDEN`.** The integration was created at tenant
scope but `environment_id` was supplied, or the reverse. The attribute has to
match the scope the integration was registered at.

**`Error: 403 BAD_PERMISSIONS` on the blueprint.** A tenant-scoped
integration cannot hold the Blueprints permissions, so the call fails even
though authentication succeeded. Recreate the integration at platform
environment scope.

**`Error: 404 page not found` with no JSON body.** `base_url` carries a path.
Supply the host on its own.

**`Error: encoded_token is invalid`** on the device enrollment resource.
something passed the `.p7m` file as raw content instead of base64. Confirm
`environments/dev/main.tf` uses `filebase64()` for the ADE token, not
`file()`.

**Postcondition failed on volume_purchasing_locations.** The async VPP
content sync did not complete in time. Open the VPP location in Jamf
Pro and wait for the content list to populate, then re-run `terraform apply`.

**`Error: state locked`.** A previous run crashed without releasing the
state lock. The error message includes a lock ID. Run
`terraform force-unlock <ID>` to clear it. Only do this if you are sure
no other apply is in progress.

**`terraform plan` shows changes you did not make.** Someone has edited a
resource in the Jamf UI. Revert the change in the UI, or update the HCL to
match. Manage each resource in one place.

**Different provider versions on different machines.** The
`.terraform.lock.hcl` is gitignored in this repository (see [CONTRIBUTING.md](CONTRIBUTING.md)
for the rationale). Run `terraform init -upgrade` on each machine to align
on the latest version that satisfies the constraints in `terraform.tf`.

---

## Further reading

- [Resources for getting started with Terraform and Jamf](https://concepts.jamf.com/guides/infrastructure-as-code/resources-for-getting-started-with-terraform-and-jamf/), curated learning resources for Jamf admins new to IaC
- [Managing Jamf configuration with Terraform: an introduction](https://concepts.jamf.com/guides/infrastructure-as-code/managing-jamf-configuration-with-terraform-an-introduction/), a hands-on walkthrough
- [Adopting Terraform for Jamf with jamformer](https://concepts.jamf.com/guides/infrastructure-as-code/adopting-terraform-for-jamf-with-jamformer/), using jamformer to bootstrap from an existing tenant
</content>
</invoke>
