# Getting started with Terraform and Jamf Platform

> **You are on the `ref-jamfplatform-starter` branch.** This is a sandbox
> companion for the Jamf IaC Enablement session. Other branches in this
> repository are unrelated.

A flat Terraform project that manages two Jamf Platform resource types against
a sandbox tenant. Flat means all `.tf` files sit at the root — no
`environments/` folders, no modules. This is the right starting point before
adding multi-environment structure.

---

## Contents

- [Learning outcomes](#learning-outcomes)
- [What you'll build](#what-youll-build)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Step 1: Software Update Blueprint](#step-1-software-update-blueprint)
- [Step 2: Safari Restrictions Blueprint](#step-2-safari-restrictions-blueprint)
- [Step 3: Compliance Benchmark](#step-3-compliance-benchmark)
- [Drift: when Jamf Platform and Terraform disagree](#drift-when-jamf-platform-and-terraform-disagree)
- [Importing existing resources](#importing-existing-resources)
- [Discovering resources with data sources](#discovering-resources-with-data-sources)
- [Cleaning up](#cleaning-up)
- [What's next](#whats-next)

---

## Learning outcomes

By the end of this session you will be able to:

- Configure the Jamf Platform Terraform provider with OAuth2 credentials
- Declare resources, understand state, and run `init`, `plan`, `apply`, and
  `destroy`
- Use data sources to read existing infrastructure and feed results into
  resources
- Build a compliance benchmark dynamically from a data source using `for`
  expressions
- Detect and respond to configuration drift using `terraform plan`
- Import existing Jamf Platform resources into Terraform management using
  `import` blocks

## What you'll build

| File | Resource | Teaches |
| --- | --- | --- |
| `blueprints.tf` | Blueprint (software update settings) | First resource, anatomy of a resource block, the `deployed` flag |
| `blueprints.tf` | Blueprint (Safari restrictions via legacy payload) | Inline JSON payloads with `legacy_payloads` |
| `compliance_benchmarks.tf` | Compliance Benchmark | Data sources, `for` expressions, async resource creation |

---

## Prerequisites

- A Jamf sandbox tenant — **do not use production**
- Git (see below)
- Terraform >= 1.11.0 (see below)
- VS Code with the HashiCorp Terraform extension (see below)
- Platform API OAuth2 credentials (see below)
- A device group Platform ID to target (see below)

### Installing git

macOS does not always ship git out of the box. Check with `git --version`. If
missing, install via Homebrew:

```bash
brew install git
```

### Installing Terraform

On macOS, the recommended approach is Homebrew:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform -version
```

For other platforms, see
[developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install).

### Recommended editor

[Visual Studio Code](https://code.visualstudio.com) with the
[HashiCorp Terraform extension](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform)
gives you syntax highlighting, auto-complete, and inline documentation for
resource attributes. It is not required but makes editing `.tf` files
significantly easier.

### Create Platform API credentials

The Jamf Platform provider authenticates via OAuth2 using credentials created
in the Jamf admin console. These are **separate** from Jamf Pro API Roles and
Clients — the Platform API is a different API surface with its own credential
management.

1. Sign in to the Jamf admin console for your sandbox tenant
2. Navigate to **Settings → API Integrations**
3. Create a new OAuth2 client with scopes for Blueprints and Compliance
   Benchmarks APIs
4. Copy the `client_id` and `client_secret` — the secret is shown only once

You also need two additional values:

- **Tenant UUID** — found in the admin console under your tenant details
- **Base URL** — the regional API gateway:
  - `https://us.apigw.jamf.com` (US)
  - `https://eu.apigw.jamf.com` (EU)
  - `https://apac.apigw.jamf.com` (APAC)

For full credential setup guidance, see the
[Platform API getting started documentation](https://developer.jamf.com/platform-api/reference/getting-started-with-platform-api).

### Find a device group Platform ID

Blueprints and compliance benchmarks target device groups using a **Platform
API UUID** — not the numeric ID used by Jamf Pro. These UUIDs are assigned by
the Platform API and are distinct from Jamf Pro group IDs even for the same
group.

The simplest Terraform-native approach to find one: add this to any `.tf` file
temporarily after completing the initial setup below, then run
`terraform apply`:

```hcl
data "jamfplatform_device_groups" "all" {}

output "device_groups" {
  value = data.jamfplatform_device_groups.all.device_groups
}
```

The output lists every group with its Platform UUID. Copy the `id` of the group
you want to target, set it as `device_group_platform_id` in `terraform.tfvars`,
and remove the data source and output blocks before continuing.

You can also filter to a specific group type:

```hcl
data "jamfplatform_device_groups" "computers" {
  filter = [
    {
      selector = "deviceType"
      argument = "COMPUTER"
    },
    {
      join_with = "and"
      selector  = "groupType"
      argument  = "STATIC"
    }
  ]
}
```

---

## Setup

### Clone

```bash
git clone --branch ref-jamfplatform-starter --single-branch https://github.com/Jamf-Concepts/terraform-jamf-platform.git
cd terraform-jamf-platform
```

### Configure credentials

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in your values:

```hcl
jamfplatform_base_url      = "https://us.apigw.jamf.com"
jamfplatform_client_id     = "your-client-id"
jamfplatform_client_secret = "your-client-secret"
jamfplatform_tenant_id     = "your-tenant-uuid"
device_group_platform_id   = "your-device-group-uuid"
```

`terraform.tfvars` is gitignored — it will never be committed.

Alternatively, export credentials as environment variables:

```bash
export TF_VAR_jamfplatform_base_url="https://us.apigw.jamf.com"
export TF_VAR_jamfplatform_client_id="..."
export TF_VAR_jamfplatform_client_secret="..."
export TF_VAR_jamfplatform_tenant_id="..."
export TF_VAR_device_group_platform_id="..."
```

### Initialise Terraform

```bash
terraform init
```

Terraform downloads the `Jamf-Concepts/jamfplatform` provider from the registry
into a local `.terraform/` cache. Run this once after cloning.

To update providers to newer versions within the declared constraints, run:

```bash
terraform init -upgrade
```

After each file you add during the session, format your code:

```bash
terraform fmt
```

A successful init ends with:

```text
Terraform has been successfully initialized!
```

---

## Step 1: Software Update Blueprint

Blueprints are the primary resource type in the Jamf Platform API. A blueprint
declares a desired configuration state and deploys it to a set of device groups
using Apple's Declarative Device Management (DDM) framework. Unlike classic MDM
profiles, DDM blueprints are stateful — the device maintains the configuration
and reports compliance back to Jamf.

Open `blueprints.tf` and replace its contents with:

```hcl
resource "jamfplatform_blueprints_blueprint" "software_update" {
  name        = "Software Update Settings"
  description = "Managed by Terraform"
  deployed    = true

  device_groups = [var.device_group_platform_id]

  software_update_settings = {
    automatic_download                 = "AlwaysOn"
    automatic_install_os_updates       = "AlwaysOn"
    automatic_install_security_updates = "AlwaysOn"
    notifications_enabled              = true
    rapid_security_response_enabled    = true
  }
}
```

**Key points:**

- Each `resource` block declares one object Terraform will create. The block
  address is `<type>.<name>` — `jamfplatform_blueprints_blueprint.software_update`.
  Terraform tracks it in state by this address.
- `deployed = true` tells the provider to deploy the blueprint immediately after
  creation. Setting `deployed = false` creates the blueprint without pushing it
  to devices — useful for drafting configuration before it goes live.
- `device_groups` takes a set of Platform UUID strings. Here it references
  the variable you configured in `terraform.tfvars`. Wrap the reference in
  `[...]` because the attribute expects a set, even with a single group.
- `software_update_settings` is one of many optional payload blocks. Each block
  maps to a specific DDM component. Only include the blocks you need — omitted
  blocks do not appear in the deployed blueprint.

Run a plan:

```bash
terraform plan
```

You should see `Plan: 1 to add`. Apply:

```bash
terraform apply
```

Type `yes` when prompted. Terraform creates the blueprint in Jamf Platform and
deploys it to the target device group. Open the Jamf admin console and confirm
the **Software Update Settings** blueprint appears in the Blueprints list with
a deployed status.

---

## Step 2: Safari Restrictions Blueprint

This step introduces `legacy_payloads` — the mechanism for delivering classic
MDM configuration profile payloads via a blueprint. Any Apple-defined payload
type (identified by a reverse-domain key like `com.apple.applicationaccess`)
can be delivered this way. This bridges the gap between new DDM-native
components and the full breadth of Apple's MDM payload library.

Open `blueprints.tf` and add the following below the first resource:

```hcl
resource "jamfplatform_blueprints_blueprint" "safari_restrictions" {
  name        = "Safari Restrictions"
  description = "Managed by Terraform"
  deployed    = true

  device_groups = [var.device_group_platform_id]

  legacy_payloads = [
    {
      payload_type = "com.apple.applicationaccess"
      settings = {
        allowSafariHistoryClearing = false
        allowSafariPrivateBrowsing = false
      }
    }
  ]
}
```

**Key points:**

- `legacy_payloads` takes a list of objects. Each object requires a
  `payload_type` (the Apple reverse-domain identifier for the MDM payload) and
  an optional `settings` map of key-value pairs. The keys and values match
  Apple's MDM protocol specification for that payload type.
- You can combine `legacy_payloads` with first-class DDM blocks like
  `software_update_settings` in a single blueprint. Each blueprint represents
  one coherent configuration boundary — grouping related settings together
  keeps the deployment unit meaningful.
- The `settings` map is passed through to the MDM payload as-is. Boolean
  values are expressed as HCL booleans (`true`/`false`), not strings.

```bash
terraform plan
terraform apply
```

Plan should show `1 to add`. Verify the **Safari Restrictions** blueprint
appears in the Jamf admin console.

---

## Step 3: Compliance Benchmark

A compliance benchmark applies CIS or STIG security rules to a device group
and monitors — or optionally enforces — compliance. Unlike blueprints, a
benchmark is built from a list of rules sourced from a versioned baseline that
changes between releases. Rather than hard-coding rule IDs, you use a data
source to read the current baseline and pass all rules to the resource
dynamically using a `for` expression.

This step introduces two new concepts:

- **Data sources** — read existing infrastructure or external data without
  managing it. Terraform fetches the data at plan time; it never creates,
  updates, or deletes a data source.
- **`for` expressions** — transform a list from one shape into another. Here
  they convert the raw rule list from the data source into the structure the
  benchmark resource expects.

Open `compliance_benchmarks.tf` and replace its contents with:

```hcl
data "jamfplatform_cbengine_rules" "cis_lvl1" {
  baseline_id = "cis_lvl1"
}

resource "jamfplatform_cbengine_benchmark" "cis_lvl1" {
  title              = "CIS Level 1"
  description        = "Managed by Terraform"
  source_baseline_id = "cis_lvl1"

  sources = [
    for s in data.jamfplatform_cbengine_rules.cis_lvl1.sources : {
      branch   = s.branch
      revision = s.revision
    }
  ]

  rules = [
    for r in data.jamfplatform_cbengine_rules.cis_lvl1.rules : {
      id      = r.id
      enabled = r.enabled
    }
  ]

  target_device_group = var.device_group_platform_id
  enforcement_mode    = "MONITOR"
}
```

**Key points:**

- `data "jamfplatform_cbengine_rules" "cis_lvl1"` fetches the current rule set
  for the `cis_lvl1` baseline from the Jamf Platform API at plan time. The
  prefix `data.` distinguishes it from a managed resource. Terraform reads it
  but never manages its lifecycle.
- The `for` expressions in `sources` and `rules` iterate over the lists
  returned by the data source and project each element into the shape the
  resource attribute expects. This means the benchmark always tracks the
  current baseline — if Jamf updates the baseline with new rules, your next
  `terraform plan` will show the diff.
- `enforcement_mode = "MONITOR"` reports compliance without enforcing
  remediation. Change to `"MONITOR_AND_ENFORCE"` to also apply corrective
  configuration to non-compliant devices.
- Benchmark creation is asynchronous — the Jamf Platform API accepts the
  request and deploys associated MDM artifacts in the background. The provider
  polls until the benchmark reaches `SYNCED` state, so `terraform apply` may
  take longer than previous steps.

```bash
terraform plan
terraform apply
```

The plan shows `1 to read` (the data source, fetched during planning) and
`1 to add` (the benchmark resource). Confirm the benchmark appears in the
Jamf admin console under Compliance Benchmarks.

---

## Drift: when Jamf Platform and Terraform disagree

Terraform's state file records the last-known configuration of every resource
it manages. If someone modifies a resource directly in the Jamf admin console
or via the Platform API, the live configuration diverges from state. Running
`terraform plan` detects this — Terraform reads the current state of each
resource from the API and compares it against the HCL. The HCL is always the
source of truth.

### Change 1: toggling deployed

In the Jamf admin console, find the **Software Update Settings** blueprint and
undeploy it manually.

Run a plan:

```bash
terraform plan
```

Terraform shows a modification:

```text
~ jamfplatform_blueprints_blueprint.software_update
    ~ deployed = false -> true
```

The `~` symbol means an in-place update. Terraform intends to redeploy the
blueprint. Running `terraform apply` does exactly that.

If you want the blueprint to remain undeployed, update `deployed = false` in
`blueprints.tf`, then re-run `terraform plan` — the plan should show no
changes.

### Change 2: modifying a payload setting

In the Jamf admin console, edit the **Safari Restrictions** blueprint and
re-enable private browsing (`allowSafariPrivateBrowsing = true`).

Run a plan:

```bash
terraform plan
```

Terraform shows the `legacy_payloads` diff and intends to revert the setting
back to `false` as declared in `blueprints.tf`. This is the core value of IaC:
the HCL is always the source of truth. Drift is detected and corrected, not
silently accepted. Running `terraform apply` restores the declared state.

---

## Importing existing resources

Import brings a resource that already exists in Jamf Platform under Terraform
management without recreating it. This is the path for blueprints or benchmarks
created in the UI before Terraform was involved.

The workflow uses an `import` block alongside
`terraform plan -generate-config-out`, which reads the live resource from the
API and generates the HCL for you.

**Before you start:** create an unmanaged blueprint in the Jamf admin console
to simulate one that exists outside Terraform. Create a blueprint named
**Passcode Policy** with a passcode requirement enabled.

### Finding the resource UUID

Platform resources are identified by UUID, not a numeric ID. Use a data source
to look it up by name. Add this temporarily to any `.tf` file:

```hcl
data "jamfplatform_blueprints_blueprint" "passcode_policy" {
  name = "Passcode Policy"
}

output "passcode_policy_id" {
  value = data.jamfplatform_blueprints_blueprint.passcode_policy.id
}
```

Run `terraform apply` and note the UUID printed in the output. Remove the data
source and output blocks.

### Write the import block

Open `imports.tf` and uncomment the blueprint block, filling in the UUID:

```hcl
import {
  to = jamfplatform_blueprints_blueprint.passcode_policy
  id = "12345678-abcd-ef01-2345-67890abcdef0"  # replace with actual UUID
}
```

Run plan with config generation:

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform reads the live blueprint from the API and writes its full resource
block to `generated.tf`. Open it and review the output — it will look something
like:

```hcl
resource "jamfplatform_blueprints_blueprint" "passcode_policy" {
  name        = "Passcode Policy"
  deployed    = true
  device_groups = ["..."]

  passcode_policy = {
    require_passcode = true
    minimum_length   = 6
  }
}
```

Copy the resource block into `blueprints.tf`. Delete the import block from
`imports.tf` and delete `generated.tf`.

Run a final plan to confirm Terraform sees no changes:

```bash
terraform plan
```

A clean plan (`No changes`) means **Passcode Policy** is now fully under
Terraform management. Any future changes must go through HCL — edits in the
admin console will show as drift on the next plan.

---

## Discovering resources with data sources

The import workflow above handles one resource at a time. For understanding
what already exists in your tenant, data sources give you a live, filterable
view. Unlike `generate-config-out`, they return structured data you can query
and feed directly into other resources.

### List all device groups

Add this temporarily to discover groups and their Platform IDs:

```hcl
data "jamfplatform_device_groups" "all_computers" {
  filter = [
    {
      selector = "deviceType"
      argument = "COMPUTER"
    }
  ]
}

output "computer_groups" {
  value = data.jamfplatform_device_groups.all_computers.device_groups
}
```

### List available compliance baselines

To see what baselines are available for benchmarks:

```hcl
data "jamfplatform_cbengine_baselines" "all" {}

output "baselines" {
  value = [
    for b in data.jamfplatform_cbengine_baselines.all.baselines :
    "${b.baseline_id}: ${b.title} (${b.rule_count} rules)"
  ]
}
```

Run `terraform apply` with either data source in place, note the output, then
remove the block before continuing.

> **Note on jamformer:** [jamformer](https://github.com/Jamf-Concepts/jamformer)
> reads an existing Jamf Pro instance and generates Terraform configuration for
> the `deploymenttheory/jamfpro` provider — policies, profiles, scripts, and
> groups. It does not cover the Jamf Platform API. For Platform resources,
> the native Terraform data sources above are the discovery path, and
> `terraform plan -generate-config-out` generates the HCL for individual
> resources you want to import.

---

## Cleaning up

To remove everything Terraform created in your sandbox:

```bash
terraform destroy
```

Terraform reads state and deletes each resource from Jamf Platform. Type `yes`
when prompted. The state file will be empty when it finishes.

Then revoke the OAuth2 client in the Jamf admin console to clean up credentials.

---

## What's next

- **`ref-jamfpro-starter` branch** — the companion starter for the
  `deploymenttheory/jamfpro` provider. Covers categories, scripts, computer
  groups, and policies with the same flat layout. A good starting point if you
  also manage Jamf Pro resources.
- **`ref-jamfpro` branch** — the next step up. Uses `environments/` +
  `modules/` structure with both `jamfpro` and `jamfplatform` providers working
  together. Shows how Jamf Pro groups are bridged to Platform blueprints using
  the cross-provider data pattern. Also covers remote state for team
  collaboration.
- **[Resources for getting started with Terraform and Jamf](https://concepts.jamf.com/guides/infrastructure-as-code/resources-for-getting-started-with-terraform-and-jamf/)** —
  curated reading for Jamf admins new to IaC.
