# Getting started with Terraform and Jamf Platform

> **You are on the `ref-jamfplatform-starter` branch.** This is a sandbox
> companion for the Jamf IaC Enablement session. Other branches in this
> repository are unrelated.

A flat Terraform project that manages three Jamf Platform resource types against
a sandbox tenant. Flat means all `.tf` files sit at the root — no
`environments/` folders, no modules. This is the same layout that
[jamformer](https://github.com/Jamf-Concepts/jamformer) produces when it reads
an existing tenant, and the right starting point before adding multi-environment
structure.

---

## Contents

- [Learning outcomes](#learning-outcomes)
- [What you'll build](#what-youll-build)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Step 1: Device Groups](#step-1-device-groups)
- [Step 2: Software Update Blueprint](#step-2-software-update-blueprint)
- [Step 3: Safari Restrictions Blueprint](#step-3-safari-restrictions-blueprint)
- [Step 4: Compliance Benchmark](#step-4-compliance-benchmark)
- [Drift: when Jamf Platform and Terraform disagree](#drift-when-jamf-platform-and-terraform-disagree)
- [Importing existing resources](#importing-existing-resources)
- [Discovering resources with jamformer](#discovering-resources-with-jamformer)
- [Cleaning up](#cleaning-up)
- [What's next](#whats-next)

---

## Learning outcomes

By the end of this session you will be able to:

- Configure the Jamf Platform Terraform provider with OAuth2 credentials
- Declare resources, understand state, and run `init`, `plan`, `apply`, and
  `destroy`
- Reference resource IDs across files and let Terraform resolve dependency
  ordering automatically
- Use data sources to read existing infrastructure and feed results into
  resources
- Build a compliance benchmark dynamically from a data source using `for`
  expressions
- Detect and respond to configuration drift using `terraform plan`
- Import existing Jamf Platform resources into Terraform management using
  `import` blocks
- Use jamformer to generate Terraform configuration from an existing tenant at
  scale

## What you'll build

| File | Resource | Teaches |
| --- | --- | --- |
| `device_groups.tf` | Device group | Standalone resource, no dependencies |
| `blueprints.tf` | Blueprint (software update settings) | Resource references, the `deployed` flag, DDM overview |
| `blueprints.tf` | Blueprint (Safari restrictions) | `legacy_payloads`, inline MDM payload syntax |
| `compliance_benchmarks.tf` | Compliance Benchmark | Data sources, `for` expressions, async resource creation |

---

## Prerequisites

- A Jamf sandbox tenant — **do not use production**
- Git (see below)
- Terraform >= 1.14.0 (see below)
- VS Code with the HashiCorp Terraform extension (see below)
- Platform API OAuth2 credentials (see below)
- jamformer (see below)

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
resource attributes. Not required but makes editing `.tf` files significantly
easier.

### Create Platform API credentials

The Jamf Platform provider authenticates via OAuth2 using an **integration**
created in **Jamf Account** at [account.jamf.com](https://account.jamf.com).

> **Beta requirement:** The Platform API Gateway is currently in beta. You must
> first enroll in the **Platform API Gateway Beta** via
> **Feedback Program → Other** in Jamf Account before the Integrations section
> becomes available.

1. Sign in to [account.jamf.com](https://account.jamf.com)
2. Enroll in the Platform API Gateway Beta under **Feedback Program → Other**
   (if not already enrolled)
3. Navigate to **Integrations** in the left navigation
4. Click **Create integration**
5. Enter a name and description, select the **Region** matching your tenant,
   select your sandbox instance under **Tenants**, and grant permissions for
   Blueprints, Compliance Benchmarks, and Device Group Inventory
6. Click **Create integration** — the Integration details panel shows your
   `client_id` and `client_secret`

> **Copy the client secret immediately.** It is not shown again after you close
> the panel.

**Finding your tenant ID:** In the Integration details panel, the scoped
tenants are shown as pills. Click any tenant pill to copy its UUID to your
clipboard. This UUID is the `tenant_id` value for the Terraform provider — it
appears in every API URL path:
`https://us.apigw.jamf.com/api/.../tenant/{tenant_id}/...`

**Base URL** — the regional API gateway:

- `https://us.apigw.jamf.com` (US)
- `https://eu.apigw.jamf.com` (EU)
- `https://apac.apigw.jamf.com` (APAC)

### Install jamformer

[jamformer](https://github.com/Jamf-Concepts/jamformer) reads an existing Jamf
tenant and generates Terraform configuration from it. For the Platform provider,
it supports Blueprints, Compliance Benchmarks, and Device Groups. Install via
Homebrew:

```bash
brew install Jamf-Concepts/tap/jamformer
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
```

`terraform.tfvars` is gitignored — it will never be committed.

Alternatively, export as environment variables:

```bash
export TF_VAR_jamfplatform_base_url="https://us.apigw.jamf.com"
export TF_VAR_jamfplatform_client_id="..."
export TF_VAR_jamfplatform_client_secret="..."
export TF_VAR_jamfplatform_tenant_id="..."
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

## Step 1: Device Groups

Device groups are the targeting mechanism for both blueprints and compliance
benchmarks — every Platform resource that scopes to devices does so through a
device group. They are the right first thing to declare because they have no
dependencies on other Platform resources.

Open `device_groups.tf` and replace its contents with:

```hcl
resource "jamfplatform_device_group" "test_machines" {
  name        = "Test Machines"
  description = "Managed by Terraform"
  group_type  = "static"
  device_type = "computer"
}
```

**Key points:**

- The block address is `jamfplatform_device_group.test_machines`. To reference
  this group's Platform UUID from another resource, use
  `jamfplatform_device_group.test_machines.id`. Terraform substitutes the
  API-assigned UUID at plan time — you never look up or hard-code UUIDs
  manually.
- `group_type = "static"` creates a static group. Members are managed manually
  in Jamf (or via the `members` attribute). Use `"smart"` with a `criteria`
  block for a dynamic smart group.
- `device_type` must be `"computer"` or `"mobile"` and cannot be changed after
  creation without replacing the resource.

Run a plan:

```bash
terraform plan
```

You should see `Plan: 1 to add`. Apply:

```bash
terraform apply
```

Type `yes` when prompted. Terraform creates the group in Jamf and records its
API-assigned UUID in `terraform.tfstate`. After apply, add your test
machine(s) to the group manually in the Jamf admin console — Terraform manages
the group definition, not its membership.

---

## Step 2: Software Update Blueprint

Blueprints are the primary configuration resource in the Jamf Platform API.
A blueprint declares a desired state and deploys it to device groups using
Apple's Declarative Device Management (DDM) framework. Unlike classic MDM
profiles, DDM is stateful — the device maintains the configuration and reports
compliance continuously.

Open `blueprints.tf` and replace its contents with:

```hcl
resource "jamfplatform_blueprints_blueprint" "software_update" {
  name        = "Software Update Settings"
  description = "Managed by Terraform"
  deployed    = true

  device_groups = [jamfplatform_device_group.test_machines.id]

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

- `device_groups = [jamfplatform_device_group.test_machines.id]` is a resource
  reference. Terraform reads the `id` attribute from the device group you just
  created and substitutes it here. Because this is a reference, Terraform knows
  the group must exist before the blueprint — you never specify ordering
  manually.
- `device_groups` takes a set of UUID strings. Even when targeting one group,
  wrap the reference in `[...]`.
- `deployed = true` tells the provider to deploy the blueprint immediately after
  creation. Set to `false` to create the blueprint without pushing it to
  devices — useful for drafting configuration before it goes live.
- `software_update_settings` is one of many optional payload blocks available
  on a blueprint. Each maps to a specific DDM component. Only include blocks
  you need — omitted blocks do not appear in the deployed blueprint.

```bash
terraform plan
terraform apply
```

Plan should show `1 to add`. Verify the **Software Update Settings** blueprint
appears in the Jamf admin console scoped to **Test Machines**.

---

## Step 3: Safari Restrictions Blueprint

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

  device_groups = [jamfplatform_device_group.test_machines.id]

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
  an optional `settings` map. The keys and values match Apple's MDM protocol
  specification for that payload type.
- Boolean values are HCL booleans (`true`/`false`), not strings.
- You can combine `legacy_payloads` with first-class DDM blocks like
  `software_update_settings` in a single blueprint. Group related settings
  together — one blueprint per configuration boundary.

```bash
terraform plan
terraform apply
```

Plan should show `1 to add`. Verify the **Safari Restrictions** blueprint
appears in the Jamf admin console scoped to **Test Machines**.

---

## Step 4: Compliance Benchmark

A compliance benchmark applies security rules from a CIS or STIG baseline to
a device group and monitors — or optionally enforces — compliance. The set of
rules in a baseline changes between releases. Rather than hard-coding rule IDs,
you use a data source to read the current baseline and pass all rules to the
resource dynamically using a `for` expression.

This step introduces two new concepts:

- **Data sources** — read existing infrastructure or external data without
  managing it. Terraform fetches the data at plan time; it never creates,
  updates, or deletes a data source.
- **`for` expressions** — transform a list from one shape into another, here
  converting the rule list from the data source into the structure the resource
  expects.

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

  target_device_group = jamfplatform_device_group.test_machines.id
  enforcement_mode    = "MONITOR"
}
```

**Key points:**

- `data "jamfplatform_cbengine_rules" "cis_lvl1"` fetches the current rule set
  from the Jamf Platform API at plan time. The `data.` prefix distinguishes it
  from a managed resource. Terraform reads it but never manages its lifecycle.
- The `for` expressions in `sources` and `rules` iterate over the lists returned
  by the data source and project each element into the expected shape. If Jamf
  updates the baseline with new rules, your next `terraform plan` will show the
  diff automatically.
- `target_device_group = jamfplatform_device_group.test_machines.id` references
  the same device group as the blueprints. Terraform resolves all dependencies
  from the reference graph — no manual ordering required.
- `enforcement_mode = "MONITOR"` reports compliance without enforcing
  remediation. Change to `"MONITOR_AND_ENFORCE"` to also apply corrective
  configuration.
- Benchmark creation is asynchronous. The provider polls until the benchmark
  reaches `SYNCED` state, so this apply may take longer than previous steps.

```bash
terraform plan
terraform apply
```

The plan shows `1 to read` (the data source, fetched during planning) and
`1 to add` (the benchmark). Confirm the benchmark appears in the Jamf admin
console under Compliance Benchmarks.

---

## Drift: when Jamf Platform and Terraform disagree

Terraform's state file records the last-known configuration. If someone
modifies a resource directly in the Jamf admin console or via the Platform API,
the live configuration diverges from state. Running `terraform plan` detects
this — Terraform reads the current state of each resource from the API and
compares it against the HCL. The HCL is always the source of truth.

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
re-enable private browsing.

Run a plan:

```bash
terraform plan
```

Terraform shows the `legacy_payloads` diff and intends to revert to the
HCL-declared values. This is the core value of IaC: the HCL is always the
source of truth. Drift is detected and corrected, not silently accepted.

---

## Importing existing resources

Import brings a resource that already exists in Jamf Platform under Terraform
management without recreating it. This is the path for device groups, blueprints,
or benchmarks created in the UI before Terraform was involved.

The workflow uses an `import` block alongside
`terraform plan -generate-config-out`, which reads the live resource from the
API and generates the HCL for you.

**Before you start:** create two unmanaged resources in the Jamf admin console
to simulate configuration that exists outside Terraform:

- A device group named **Terraform Managed** (static, computer)
- A blueprint named **Passcode Policy** with a passcode requirement enabled

### Finding resource UUIDs

Platform resources are identified by UUID. Use a data source to look one up
by name. Add this temporarily to any `.tf` file:

```hcl
data "jamfplatform_blueprints_blueprint" "passcode_policy" {
  name = "Passcode Policy"
}

output "passcode_policy_id" {
  value = data.jamfplatform_blueprints_blueprint.passcode_policy.id
}
```

Run `terraform apply` and note the UUID in the output. Remove the data source
and output blocks.

For the device group, use `jamfplatform_device_groups` (plural — the list data
source):

```hcl
data "jamfplatform_device_groups" "find_terraform_managed" {
  filter = [{ selector = "name", argument = "Terraform Managed" }]
}

output "terraform_managed_id" {
  value = data.jamfplatform_device_groups.find_terraform_managed.device_groups[0].id
}
```

### Import 1: a device group

Open `imports.tf` and uncomment the device group block, filling in the UUID:

```hcl
import {
  to = jamfplatform_device_group.terraform_managed
  id = "12345678-abcd-ef01-2345-67890abcdef0"  # replace with actual UUID
}
```

Run plan with config generation:

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform reads the live device group from the API and writes its full resource
block to `generated.tf`. Review the output and copy the resource block into
`device_groups.tf`. Delete the import block from `imports.tf` and delete
`generated.tf`.

Run a final plan to confirm no changes:

```bash
terraform plan
```

A clean plan means the device group is now fully under Terraform management.

### Import 2: a blueprint

Uncomment the blueprint block in `imports.tf`, filling in the UUID:

```hcl
import {
  to = jamfplatform_blueprints_blueprint.passcode_policy
  id = "your-uuid-here"
}
```

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform generates the blueprint resource block. Copy it into `blueprints.tf`,
delete the import block from `imports.tf` and `generated.tf`, then run
`terraform plan` to verify a clean result.

If the blueprint targets a device group that is now managed by Terraform, update
the `device_groups` attribute in the generated block to use the resource
reference rather than the hardcoded UUID:

```hcl
# Replace this:
device_groups = ["12345678-abcd-ef01-2345-67890abcdef0"]

# With this:
device_groups = [jamfplatform_device_group.test_machines.id]
```

> **This is exactly the problem jamformer solves.** When jamformer generates
> configuration from an existing tenant, it detects UUID references between
> resources and replaces them with Terraform symbolic references automatically.
> The result is immediately correct HCL — no manual UUID replacement required.

---

## Discovering resources with jamformer

The manual import workflow above handles one or two resources. For a real
tenant with dozens of blueprints and device groups, it does not scale.
jamformer solves this — it reads the entire tenant and generates Terraform
configuration in one pass.

### How jamformer works with the Platform provider

For Jamf Pro resources, jamformer calls the Jamf Pro API directly. For Jamf
Platform resources, it uses a different mechanism: it runs `terraform query`
against your tenant, which uses the provider's built-in list resources
capability. This is why Terraform 1.14+ is required.

jamformer uses its own set of environment variables for credentials — separate
from the `TF_VAR_*` variables you use for Terraform operations:

```bash
export JAMF_URL="https://us.apigw.jamf.com"
export JAMF_CLIENT_ID="your-client-id"
export JAMF_CLIENT_SECRET="your-client-secret"
export JAMF_TENANT_ID="your-tenant-uuid"
```

### Running jamformer

Create a handful of additional resources in your sandbox — device groups, a
blueprint, a compliance benchmark — using the Jamf admin console. Then run
jamformer against the tenant:

```bash
jamformer -provider jamfplatform
```

jamformer is designed to be run interactively. Follow its prompts to select
which resource types to discover and where to write the output.

To see available resource types for the Platform provider:

```bash
jamformer -list-resources -provider jamfplatform
```

### What to look for in the output

- **Per-resource-type files** (`device_groups.tf`, `blueprints.tf`,
  `compliance_benchmarks.tf`) — same naming convention as this project.
- **`_import.tf` files** (`blueprints_import.tf`, `device_groups_import.tf`,
  etc.) — jamformer generates import blocks alongside each resource file. Use
  them the same way as `imports.tf` in this project: run `terraform plan`,
  verify a clean result, then remove the import blocks.
- **Resolved UUID references** — this is the key difference from
  `generate-config-out`. When jamformer sees a blueprint's `device_groups`
  attribute containing a UUID that matches a discovered device group, it
  replaces the UUID with a symbolic resource reference:

  ```hcl
  # generate-config-out produces:
  device_groups = ["fce3d9a5-8660-42ff-a95e-625e7b53b48a"]

  # jamformer produces:
  device_groups = [jamfplatform_device_group.staff_macs.id]
  ```

  The same resolution applies to `target_device_group` in compliance
  benchmarks. The dependency graph you built manually in this session is what
  jamformer generates automatically.

- **`provider.tf` and `variables.tf`** — jamformer writes full provider
  configuration in the same format as this project, ready to use.

The file naming conventions in this project are intentionally aligned with
jamformer's output so that moving from a jamformer export into a structured
project is a copy, not a rewrite.

---

## Cleaning up

To remove everything Terraform created in your sandbox:

```bash
terraform destroy
```

Terraform reads state and deletes each resource from Jamf Platform. Type `yes`
when prompted. The state file will be empty when it finishes.

Then delete the integration in [account.jamf.com](https://account.jamf.com) under **Integrations** to clean up credentials.

---

## What's next

- **`ref-jamfpro-starter` branch** — the companion starter for the
  `deploymenttheory/jamfpro` provider. Covers categories, scripts, computer
  groups, and policies with the same flat layout.
- **`ref-jamfpro` branch** — the next step up. Uses `environments/` +
  `modules/` structure with both `jamfpro` and `jamfplatform` providers working
  together. Shows the cross-provider data pattern: Jamf Pro groups are bridged
  to Platform blueprints via a data source that translates numeric Jamf Pro IDs
  to Platform UUIDs. Also covers remote state for team collaboration.
- **[Resources for getting started with Terraform and Jamf](https://concepts.jamf.com/guides/infrastructure-as-code/resources-for-getting-started-with-terraform-and-jamf/)** —
  curated reading for Jamf admins new to IaC.
