# Getting started with Terraform and the Jamf Platform API

> **You are on the `ref-jamfplatform-starter` branch.** This is a sandbox
> companion for the Jamf IaC Enablement session. Other branches in this
> repository are unrelated.

A flat Terraform project that manages three Platform API resource types against
a sandbox tenant. Flat means all `.tf` files sit at the root, with no
`environments/` folders and no modules. This is the same layout that
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
- [Drift: when the Platform API and Terraform disagree](#drift-when-the-platform-api-and-terraform-disagree)
- [Importing existing resources](#importing-existing-resources)
- [Discovering resources with jamformer](#discovering-resources-with-jamformer)
- [Cleaning up](#cleaning-up)
- [What's next](#whats-next)

---

## Learning outcomes

By the end of this session you will be able to:

- Configure the Platform API Terraform provider with OAuth2 credentials
- Declare resources, understand state, and run `init`, `plan`, `apply`, and
  `destroy`
- Reference resource IDs across files and let Terraform resolve dependency
  ordering
- Use data sources to read existing infrastructure and feed results into
  resources
- Build a compliance benchmark from a data source and hand-picked rules with
  custom ODV values
- Detect and respond to configuration drift using `terraform plan`
- Import existing Platform API resources into Terraform management using
  `import` blocks
- Use jamformer to generate Terraform configuration from an existing tenant at
  scale

## What you'll build

| File | Resource | Teaches |
| --- | --- | --- |
| `device_groups.tf` | Device group | Standalone resource, no dependencies |
| `blueprints.tf` | Blueprint (software update settings) | Resource references, the `deployed` flag, `component_blocks`, DDM overview |
| `blueprints.tf` | Blueprint (Safari restrictions) | `legacy_payloads`, inline MDM payload syntax |
| `compliance_benchmarks.tf` | Compliance Benchmark | Data sources, hand-picked rules, ODV values, async resource creation |

---

## Prerequisites

- A Jamf sandbox tenant. **Do not use production**
- Git (see below)
- Terraform >= 1.14.0 (see below)
- VS Code with the HashiCorp Terraform extension (see below)
- Platform API OAuth2 credentials (see below)
- jamf-cli (see below)
- jamformer (see below)

### Installing git

macOS does not always ship git out of the box. Check with `git --version`. If
missing, install via Homebrew:

```bash
brew install git
```

### Installing Terraform

On macOS, install it with Homebrew:

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
resource attributes. It is optional, and editing `.tf` files is harder without
it.

### Create Platform API credentials

The Platform API provider authenticates via OAuth2 using an **integration**
you create in **Jamf Account** at [account.jamf.com](https://account.jamf.com).

1. Sign in to [account.jamf.com](https://account.jamf.com)
2. Navigate to **Integrations** in the left navigation
3. Click **Create integration**
4. Enter a name and description, select the **Region** matching your instance,
   and scope the integration to the **platform environment** holding your
   sandbox
5. Grant these permissions. The picker groups them by category, with a
   checkbox per action:

   | Category | Permission | Actions |
   |---|---|---|
   | Inventory | Device groups | Create, Read, Update, Delete |
   | Deployment | Blueprints | Create, Read, Update, Delete |
   | Compliance | Compliance Benchmarks | Create, Read, Delete |

6. Click **Create integration**. The Integration details panel then shows your
   `client_id` and `client_secret`

> **Copy the client secret now.** Jamf Account never shows it again once you
> close the panel.

> **Scope the integration to a platform environment, not a single tenant.** A
> platform environment groups tenants across product types. Jamf Account offers
> the Blueprints and Compliance Benchmarks permissions only at that scope.

**Finding your environment ID:** click the platform environment shown in the
Integration details panel to copy its UUID. That is the `environment_id` value
for the Terraform provider.

**Base URL**, the regional API gateway:

- `https://us.api.jamfcloud.com` (US)
- `https://eu.api.jamfcloud.com` (EU)
- `https://apac.api.jamfcloud.com` (APAC)

### Install and configure jamf-cli

You use [jamf-cli](https://github.com/Jamf-Concepts/jamf-cli) during the
import exercise to create unmanaged resources and look up their UUIDs. Install
it via Homebrew:

```bash
brew install Jamf-Concepts/tap/jamf-cli
```

Configure a platform profile pointing at the same gateway and platform
environment you configured for Terraform:

```bash
jamf-cli platform setup
```

Follow the prompts to enter your gateway URL, environment ID, and OAuth2
credentials. Choose a memorable profile name when it asks, because you pass that
name to every jamf-cli command with `-p <profile>`.

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
jamfplatform_base_url       = "https://us.api.jamfcloud.com"
jamfplatform_client_id      = "your-client-id"
jamfplatform_client_secret  = "your-client-secret"
jamfplatform_environment_id = "your-environment-uuid"
```

`terraform.tfvars` is gitignored, so git will not commit it.

Or export the values as environment variables:

```bash
export TF_VAR_jamfplatform_base_url="https://us.api.jamfcloud.com"
export TF_VAR_jamfplatform_client_id="..."
export TF_VAR_jamfplatform_client_secret="..."
export TF_VAR_jamfplatform_environment_id="..."
```

### Initialise Terraform

```bash
terraform init
```

Terraform downloads the `Jamf-Concepts/jamfplatform` Platform API provider from the registry
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
benchmarks. Any Platform resource that scopes to devices does so through a
device group. Declare them first, because they depend on no other Platform
resource.

Open `device_groups.tf` and replace its contents with:

```hcl
resource "jamfplatform_device_group" "test_machines" {
  name        = "Test Machines"
  description = "Managed by Terraform"
  group_type  = "smart"
  device_type = "computer"

  criteria = [
    {
      criteria = "Operating System Version"
      operator = "greater than or equal"
      value    = "14.0"
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "is"
      value    = "C02XY1ZTEST"
    }
  ]
}
```

**Key points:**

- The block address is `jamfplatform_device_group.test_machines`. To reference
  this group's Platform UUID from another resource, use
  `jamfplatform_device_group.test_machines.id`. Terraform substitutes the
  API-assigned UUID at plan time, so you never look up or hard-code a UUID.
- `criteria` is a list of evaluation rules. Each entry after the first needs
  `and_or` set to `"and"` or `"or"` to define how it joins the previous rule.
  The first entry omits `and_or`.
- Replace `"C02XY1ZTEST"` with the serial number of your test machine so the
  group matches it. The OS version criterion keeps the scope narrow.
- `device_type` must be `"computer"` or `"mobile"`. Terraform has to replace the
  resource to change it after creation.

Run a plan:

```bash
terraform plan
```

You should see `Plan: 1 to add`. Apply:

```bash
terraform apply
```

Type `yes` when prompted. Terraform creates the group in Jamf and records its
API-assigned UUID in `terraform.tfstate`. The criteria determine membership: any
enrolled Mac running macOS 14.0 or later appears in the group.

---

## Step 2: Software Update Blueprint

Blueprints are the primary configuration resource in the Jamf Platform API.
A blueprint declares a desired state and deploys it to device groups using
Apple's Declarative Device Management (DDM) framework. Unlike classic MDM
profiles, DDM is stateful: the device holds the configuration and keeps
reporting compliance.

You author a blueprint with `component_blocks`, an ordered list. Each block
appears as a step in the Jamf Blueprints editor, with its own name and its own
set of component payloads. Jamf applies the blocks in the order you list them.

Open `blueprints.tf` and replace its contents with:

```hcl
resource "jamfplatform_blueprints_blueprint" "software_update" {
  name        = "Software Update Settings"
  description = "Managed by Terraform"
  deployed    = true

  device_groups = [jamfplatform_device_group.test_machines.id]

  component_blocks = [
    {
      name = "Software Update Settings"
      software_update_settings = {
        automatic_download                 = "AlwaysOn"
        automatic_install_os_updates       = "AlwaysOn"
        automatic_install_security_updates = "AlwaysOn"
        notifications_enabled              = true
        rapid_security_response_enabled    = true
      }
    },
  ]
}
```

**Key points:**

- `device_groups = [jamfplatform_device_group.test_machines.id]` is a resource
  reference. Terraform reads the `id` attribute from the device group you
  created and substitutes it here. Because this is a reference, Terraform knows
  the group must exist before the blueprint, so you never specify ordering
  yourself.
- `device_groups` takes a set of UUID strings. Even when targeting one group,
  wrap the reference in `[...]`.
- `deployed = true` tells the provider to deploy the blueprint as soon as it
  creates it. Set `false` to create the blueprint without pushing it to devices,
  which suits drafting configuration before it goes live.
- `component_blocks` is a list of blocks. Each block takes an optional `name`
  and one or more component payloads, here `software_update_settings`, which
  maps to a DDM component. A block may carry more than one component, and a
  blueprint may list several blocks, each a separate step applied in order.
  Include only the components you need. Components you omit do not appear in the
  deployed blueprint.
- The valid values for `automatic_*` attributes are `"AlwaysOn"`, `"AlwaysOff"`,
  and `"Allowed"`. The Jamf UI displays `"AlwaysOff"` as **Never**. Write the
  API values in HCL, not the UI labels.

```bash
terraform plan
terraform apply
```

Plan should show `1 to add`. Verify the **Software Update Settings** blueprint
appears in the Jamf UI scoped to **Test Machines**.

---

## Step 3: Safari Restrictions Blueprint

This step introduces `legacy_payloads`, the mechanism for delivering classic
MDM configuration profile payloads through a blueprint. A blueprint can carry
any Apple-defined payload type, identified by a reverse-domain key like
`com.apple.applicationaccess`. That puts the DDM-native components and Apple's
older MDM payload library behind one resource.

Open `blueprints.tf` and add the following below the first resource:

```hcl
resource "jamfplatform_blueprints_blueprint" "safari_restrictions" {
  name        = "Safari Restrictions"
  description = "Managed by Terraform"
  deployed    = true

  device_groups = [jamfplatform_device_group.test_machines.id]

  component_blocks = [
    {
      name = "Safari Restrictions"
      legacy_payloads = [
        {
          payload_type = "com.apple.applicationaccess"
          settings = jsonencode({
            allowSafariHistoryClearing = false
            allowSafariPrivateBrowsing = false
          })
        }
      ]
    },
  ]
}
```

**Key points:**

- `legacy_payloads` lives inside a component block and takes a list of objects.
  Each object requires a `payload_type` (the Apple reverse-domain identifier for
  the MDM payload) and an optional `settings`, a JSON object string you write
  with `jsonencode({ ... })`. The keys and values match Apple's MDM protocol
  specification for that payload type.
- Inside `jsonencode({ ... })`, boolean values are HCL booleans (`true`/`false`),
  not strings.
- You can combine `legacy_payloads` with first-class DDM components like
  `software_update_settings`, in the same block or across several blocks of one
  blueprint. Group related settings together, one blueprint per configuration
  boundary.

```bash
terraform plan
terraform apply
```

Plan should show `1 to add`. Verify the **Safari Restrictions** blueprint
appears in the Jamf UI scoped to **Test Machines**.

---

## Step 4: Compliance Benchmark

A compliance benchmark applies security rules from a baseline to a device
group, then either monitors compliance or enforces it. Jamf ships a range of
baselines. This step introduces **data sources**, which read existing data from
an API without Terraform managing the result. The compliance rules live in Jamf,
and Terraform only ever reads them.

### Discover available baselines

A benchmark starts from a named baseline. The
`jamfplatform_cbengine_baselines` data source lists the ones your tenant offers.
Open `compliance_benchmarks.tf` and replace its contents with:

```hcl
data "jamfplatform_cbengine_baselines" "all" {}

output "available_baselines" {
  value = [
    for b in data.jamfplatform_cbengine_baselines.all.baselines :
    "${b.baseline_id}: ${b.title} (${b.rule_count} rules)"
  ]
}
```

```bash
terraform plan
terraform apply
```

The output lists each available baseline with its ID, title, and rule count:

```text
available_baselines = [
  "cis_lvl1: CIS Benchmark - Level 1 (110 rules)",
  "cis_lvl2: CIS Benchmark - Level 2 (132 rules)",
  ...
]
```

Note the `baseline_id` values. You use one in the next section. Remove the data
source and output block from `compliance_benchmarks.tf` before continuing.

### Inspect the baseline

With a baseline ID in hand, inspect its rules before creating the benchmark.
Replace the contents of `compliance_benchmarks.tf` with:

```hcl
data "jamfplatform_cbengine_rules" "cis_lvl1" {
  baseline_id = "cis_lvl1"
}

output "cis_lvl1_rules" {
  value = [
    for r in data.jamfplatform_cbengine_rules.cis_lvl1.rules :
    r.odv_hint != null ? "${r.id}: ${r.title} [ODV: ${r.odv_hint}]" : "${r.id}: ${r.title}"
  ]
}
```

**Key points:**

- `data "jamfplatform_cbengine_rules"` fetches the rule set from the Platform
  API at plan time. The `data.` prefix marks it as a read: Terraform never
  creates, updates or deletes it.
- `output` blocks print values after apply. The `for` expression projects each
  rule into a readable string. Rules tagged with `[ODV: ...]` require an
  **organisation-defined value**, a parameter you supply such as a password
  length or a timeout in days. You set these with `odv_value` on individual
  rules in the benchmark resource.

```bash
terraform plan
terraform apply
```

The plan shows `1 to read` and `1 to add` (the output). After apply, the
terminal prints every rule in the `cis_lvl1` baseline. To save it as a file:

```bash
terraform output -json cis_lvl1_rules | jq -r '.[]' > cis_lvl1_rules.txt
```

Review the list. It is the full set of rules the benchmark will manage. Remove
the `output` block from `compliance_benchmarks.tf` before the next step.

### Create the benchmark

From the list you inspected, pick the rules relevant to your organisation.
Remove the `output` block from `compliance_benchmarks.tf`, then add the
benchmark resource below the data source:

```hcl
resource "jamfplatform_cbengine_benchmark" "cis_lvl1" {
  title              = "CIS Level 1"
  description        = "Managed by Terraform"
  source_baseline_id = "cis_lvl1"

  rules = [
    { id = "os_firewall_log_enable",                      enabled = true },
    { id = "os_gatekeeper_enable",                        enabled = true },
    { id = "system_settings_filevault_enforce",           enabled = true },
    { id = "pwpolicy_minimum_length_enforce",             enabled = true, odv_value = "15" },
    { id = "system_settings_screensaver_timeout_enforce", enabled = true, odv_value = "300" },
  ]

  # Optional: scope the benchmark to specific major OS versions. Omit this to
  # target every version the baseline supports. Valid values come from
  # data.jamfplatform_cbengine_rules.cis_lvl1.available_os_versions.
  selected_os_versions = [
    { os_type = "MAC_OS", os_version = 26 }, # 26 = Tahoe, 15 = Sequoia, 14 = Sonoma
  ]

  target_device_groups = [jamfplatform_device_group.test_machines.id]
  enforcement_mode      = "MONITOR"
}
```

**Key points:**

- Rule IDs come from the output you inspected in the previous step. Include
  only the rules your organisation wants to track.
- Rules that appeared with `[ODV: ...]` in the output accept an `odv_value`, a
  parameter like a password length or a timeout in seconds. Rules without an ODV
  hint take none.
- `selected_os_versions` is optional. Omit it and the benchmark targets every
  OS version the baseline supports; supply a subset of `{ os_type, os_version }`
  pairs to scope it to specific major versions (e.g. macOS 26 = Tahoe). The
  data source's `available_os_versions` attribute holds the valid values.
  Inspect it the same way you inspected the rules.
- `target_device_groups = [jamfplatform_device_group.test_machines.id]`
  references the same device group as the blueprints. It takes a set, so one
  benchmark can target several groups at once. Terraform resolves the
  dependencies from the reference graph, so you order nothing by hand.
- `enforcement_mode = "MONITOR"` reports compliance without enforcing
  remediation. Change to `"MONITOR_AND_ENFORCE"` to also apply corrective
  configuration.

```bash
terraform plan
terraform apply
```

Confirm the benchmark appears in the Jamf UI under Compliance
Benchmarks.

---

## Drift: when the Platform API and Terraform disagree

Running `terraform plan` compares the HCL against the live state of each
resource. Two situations surface diffs: you update the HCL to a new desired
state, or someone changes a resource in the Jamf UI or through the Platform API
without Terraform. Terraform shows what will change in both cases, and the HCL
stays the source of truth.

### Change 1: updating desired state in HCL

In `blueprints.tf`, change `automatic_install_security_updates` from
`"AlwaysOn"` to `"AlwaysOff"`:

```hcl
automatic_install_security_updates = "AlwaysOff"
```

Run a plan:

```bash
terraform plan
```

Terraform shows a modification:

```text
~ jamfplatform_blueprints_blueprint.software_update
    ~ component_blocks = [
        ~ {
              name                     = "Software Update Settings"
            ~ software_update_settings = {
                ~ automatic_install_security_updates = "AlwaysOn" -> "AlwaysOff"
                  # (4 unchanged attributes hidden)
              }
          },
      ]
```

The `~` symbol means an in-place update. The plan also shows computed fields
like `created`, `updated` and `deployment_state` moving to
`(known after apply)`. Those are read-only attributes Terraform refreshes on
every apply, not configuration drift. Read the `software_update_settings` diff
nested inside `component_blocks`. Change the value back to `"AlwaysOn"` and
apply to see the reverse diff.

### Change 2: modifying a payload setting

In the Jamf UI, edit the **Safari Restrictions** blueprint and
re-enable private browsing.

Run a plan:

```bash
terraform plan
```

Terraform shows the `legacy_payloads` diff and plans to restore the
HCL-declared values. The next apply overwrites your UI change.

---

## Importing existing resources

Import brings a resource that already exists in the Platform API under Terraform
management without recreating it. Use it for a device group, blueprint or
benchmark someone built in the UI before you brought Terraform in.

The workflow uses an `import` block alongside
`terraform plan -generate-config-out`, which reads the live resource from the
API and generates the HCL for you.

**Before you start:** create two unmanaged resources to simulate configuration
that exists outside Terraform.

> If you ran `jamf-cli platform setup` during prerequisites, that profile is the
> default, so the commands below need no `-p` flag.

**Device group.** A criteria-based smart group needs JSON input for the
`criteria` array. Write the payload to a temp file, then create it:

```bash
cat > /tmp/import_group.json << 'EOF'
{
  "name": "Terraform Managed",
  "description": "Created outside Terraform",
  "groupType": "SMART",
  "deviceType": "COMPUTER",
  "criteria": [
    {
      "attributeName": "Serial Number",
      "attributeValue": "C02IMPORT0001",
      "operator": "IS",
      "joinType": "AND",
      "order": 0,
      "hasOpeningParenthesis": false,
      "hasClosingParenthesis": false
    }
  ]
}
EOF
jamf-cli pro platform-device-groups create --file /tmp/import_group.json
```

**Blueprint.** Create this one in the Jamf UI: add a blueprint named
**Passcode Policy**, scoped to the **Terraform Managed** device group you
created.

Then find their UUIDs:

```bash
jamf-cli pro platform-device-groups list -o table
jamf-cli pro blueprints list -o table
```

Note the `ID` value for each. You use them in the import blocks.

### Import 1: a device group

Open `imports.tf` and uncomment the device group block, filling in the UUID:

```hcl
import {
  provider = jamfplatform
  to       = jamfplatform_device_group.terraform_managed
  id       = "12345678-abcd-ef01-2345-67890abcdef0" # replace with actual UUID
}
```

Include `provider = jamfplatform`. Terraform works out which provider serves a
resource type from the block that declares it, and no block declares
`jamfplatform_device_group.terraform_managed` yet. That is what you are about to
generate. Without the argument, Terraform guesses `hashicorp/jamfplatform` and
fails with `unavailable provider`.

Run plan with config generation:

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform reads the live device group from the API and writes its full resource
block to `generated.tf`. Review the output and copy the **whole** resource block
into `device_groups.tf`, then delete `generated.tf`. Leave the import block in
`imports.tf` for now, but **remove its `provider` argument**. The target has a
resource block now, and Terraform rejects the argument on an import block whose
target is already configured: `Invalid import provider argument`.

Copy the generated block as-is; any attributes you drop will show as drift on
the next plan.

Run apply to perform the import. Import blocks execute on apply, not plan:
`-generate-config-out` reads the API and writes HCL without touching state.

```bash
terraform apply
```

Once apply completes, delete the import block from `imports.tf`.

Run a final plan to confirm no changes:

```bash
terraform plan
```

A clean plan means the device group is under Terraform management.

### Import 2: a blueprint

Uncomment the blueprint block in `imports.tf`, filling in the UUID:

```hcl
import {
  provider = jamfplatform
  to       = jamfplatform_blueprints_blueprint.passcode_policy
  id       = "your-uuid-here"
}
```

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform generates the blueprint resource block. Copy the **whole** block into
`blueprints.tf` and delete `generated.tf`. Leave the import block in
`imports.tf` for now, again removing its `provider` argument.

If the blueprint targets a device group that is now managed by Terraform, update
the `device_groups` attribute in the generated block to use the resource
reference rather than the hardcoded UUID:

```hcl
# Replace this:
device_groups = ["12345678-abcd-ef01-2345-67890abcdef0"]

# With this:
device_groups = [jamfplatform_device_group.terraform_managed.id]
```

> **This is the problem jamformer solves.** Reading an existing tenant,
> jamformer spots UUID references between resources and writes Terraform
> symbolic references in their place. The HCL comes out correct, with no UUID
> replacement left for you to do.

Run apply to perform the import:

```bash
terraform apply
```

Once apply completes, delete the import block from `imports.tf`.

Run a final plan to verify a clean result:

```bash
terraform plan
```

---

## Discovering resources with jamformer

The import workflow above handles one or two resources by hand. It does not
scale to a tenant holding dozens of blueprints and device groups. jamformer
reads the whole tenant and generates Terraform configuration in one pass.

### How jamformer works with the Platform provider

For Jamf Pro resources, jamformer calls the Jamf Pro API. For Jamf Platform
resources it runs `terraform query` against your tenant, which drives the
provider's built-in list resources. Terraform 1.14 introduced that command,
which is why this project requires it.

### Running jamformer

Create a few more resources in your sandbox through the Jamf UI: a device
group, a blueprint and a compliance benchmark. Then run jamformer against the
tenant:

```bash
jamformer -provider jamfplatform
```

jamformer runs interactively. Follow its prompts to pick which resource types
to discover and where to write the output.

To see available resource types for the Platform provider:

```bash
jamformer -list-resources -provider jamfplatform
```

### What to look for in the output

- **Per-resource-type files** (`device_groups.tf`, `blueprints.tf`,
  `compliance_benchmarks.tf`), following the same naming convention as this
  project.
- **`_import.tf` files** (`blueprints_import.tf`, `device_groups_import.tf`,
  and so on). jamformer writes import blocks alongside each resource file. Use
  them the same way as `imports.tf` in this project: run `terraform plan`,
  verify a clean result, then remove the import blocks.
- **Resolved UUID references**, the one thing `generate-config-out` will not do
  for you. jamformer writes a symbolic resource reference wherever a blueprint's
  `device_groups` attribute holds a UUID matching a discovered device group:

  ```hcl
  # generate-config-out produces:
  device_groups = ["fce3d9a5-8660-42ff-a95e-625e7b53b48a"]

  # jamformer produces:
  device_groups = [jamfplatform_device_group.staff_macs.id]
  ```

  The same resolution applies to `target_device_groups` in compliance
  benchmarks. jamformer builds the dependency graph you wired up by hand in this
  session.

- **`provider.tf` and `variables.tf`**, holding full provider configuration in
  the same format as this project, ready to use.

This project borrows jamformer's file naming on purpose, so moving a jamformer
export into a structured project is a copy rather than a rewrite.

---

## Cleaning up

To remove everything Terraform created in your sandbox:

```bash
terraform destroy
```

Terraform reads state and deletes each resource from the Platform API. Type `yes`
when prompted. The state file will be empty when it finishes.

Then delete the integration in [account.jamf.com](https://account.jamf.com) under **Integrations** to clean up credentials.

---

## What's next

- **`ref-jamfpro-starter` branch**, the companion starter for the
  `deploymenttheory/jamfpro` provider. It covers categories, scripts, computer
  groups, and policies in the same flat layout.
- **`ref-jamfpro` branch**, the next step up. It uses `environments/` and
  `modules/` structure with the `jamfpro` and `jamfplatform` providers working
  together, and shows the cross-provider data pattern: a data source bridges
  Jamf Pro groups to Platform blueprints, translating numeric Jamf Pro IDs to
  Platform UUIDs. It also covers remote state for team collaboration.
- **[Resources for getting started with Terraform and Jamf](https://concepts.jamf.com/guides/infrastructure-as-code/resources-for-getting-started-with-terraform-and-jamf/)**,
  curated reading for Jamf admins new to IaC.
