# Getting started with Terraform and Jamf Pro

> **You are on the `ref-jamfpro-starter` branch.** This is a sandbox companion
> for the Jamf IaC Enablement session. Other branches in this repository are
> unrelated.

A flat Terraform project that manages four Jamf Pro resource types against a
sandbox instance. Flat means all `.tf` files sit at the root, with no
`environments/` folders, no modules. This is the same layout that
[jamformer](https://github.com/Jamf-Concepts/jamformer) produces when it reads
an existing Jamf Pro instance, and the right starting point before adding
multi-environment structure.

---

## Contents

- [Learning outcomes](#learning-outcomes)
- [What you'll build](#what-youll-build)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Step 1: Categories](#step-1-categories)
- [Step 2: Scripts](#step-2-scripts)
- [Step 3: Static Computer Groups](#step-3-static-computer-groups)
- [Step 4: Policies](#step-4-policies)
- [Drift: when Jamf Pro and Terraform disagree](#drift-when-jamf-pro-and-terraform-disagree)
- [Importing existing resources](#importing-existing-resources)
- [Discovering resources with jamformer](#discovering-resources-with-jamformer)
- [Cleaning up](#cleaning-up)
- [What's next](#whats-next)

---

## Learning outcomes

By the end of this session you will be able to:

- Configure the Jamf Platform Terraform provider with OAuth2 credentials
- Declare resources, understand state, and run `init`, `plan`, `apply`, and `destroy`
- Reference resource IDs across files and let Terraform resolve dependency ordering
- Read external file content into a resource attribute using `file()`
- Detect and respond to configuration drift using `terraform plan`
- Import existing Jamf Pro resources into Terraform management using `import` blocks
- Use jamformer to generate Terraform configuration from an existing instance at scale

## What you'll build

| File | Resource | Teaches |
| --- | --- | --- |
| `categories.tf` | Categories | First resource, anatomy of a resource block |
| `scripts.tf` | Script | Reading a file with `file()`, referencing another resource's ID |
| `static_computer_groups.tf` | Static computer group | Standalone resource, no dependencies |
| `policies.tf` | Policy | Composing resources: category, group, and script referenced in one block |

---

## Prerequisites

- A Jamf Pro sandbox instance. **Do not use production**
- Git (see below)
- Terraform >= 1.13.0 (see below)
- VS Code with the HashiCorp Terraform extension (see below)
- jamf-cli (see below)
- jamformer (see below)
- Platform API credentials from Jamf Account (see below)

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

For other platforms, see [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install).

### Recommended editor

[Visual Studio Code](https://code.visualstudio.com) with the
[HashiCorp Terraform extension](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform)
gives you syntax highlighting, auto-complete, and inline documentation for
resource attributes. It is optional, and editing `.tf` files is harder without
it.

### Create Platform API credentials

The Jamf Platform Terraform provider authenticates via OAuth2 using an
**integration** created in **Jamf Account** at
[account.jamf.com](https://account.jamf.com).

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
   | Organizational context | Categories | Create, Read, Update, Delete |
   | Deployment | Scripts | Create, Read, Update, Delete |
   | Deployment | Policies | Create, Read, Update, Delete |
   | Inventory | Device groups | Create, Read, Update, Delete |

6. Click **Create integration**. The Integration details panel then shows your
   `client_id` and `client_secret`

> **Copy the client secret now.** Jamf Account never shows it again once you
> close the panel.

**Finding your environment ID:** click the platform environment shown in the
Integration details panel to copy its UUID. That is the `environment_id` value
for the Terraform provider.

**Base URL**, the regional API gateway:

- `https://us.api.jamfcloud.com` (US)
- `https://eu.api.jamfcloud.com` (EU)
- `https://apac.api.jamfcloud.com` (APAC)

### Install and configure jamf-cli

You use [jamf-cli](https://github.com/Jamf-Concepts/jamf-cli) during the
import exercise to create unmanaged resources and look up their IDs. Install
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
credentials.
This profile becomes your default, so commands below don't need `-p`. If you
later add a second profile, pass `-p <profile>` to pick between them.

### Install jamformer

[jamformer](https://github.com/Jamf-Concepts/jamformer) reads an existing Jamf
Pro instance and generates Terraform configuration from it. You run it later
in this session to see how to bootstrap a project from existing resources at
scale.

```bash
brew install Jamf-Concepts/tap/jamformer
```

---

## Setup

### Clone

```bash
git clone --branch ref-jamfpro-starter --single-branch https://github.com/Jamf-Concepts/terraform-jamf-platform.git
cd terraform-jamf-platform
```

### Configure credentials

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in your values:

```hcl
jamfplatform_base_url       = "https://us.api.jamfcloud.com"
jamfplatform_environment_id = "your-environment-uuid"
jamfplatform_client_id      = "your-client-id"
jamfplatform_client_secret  = "your-client-secret"
```

`terraform.tfvars` is gitignored, so git will not commit it.

Or export credentials as environment variables:

```bash
export TF_VAR_jamfplatform_base_url="https://us.api.jamfcloud.com"
export TF_VAR_jamfplatform_environment_id="your-environment-uuid"
export TF_VAR_jamfplatform_client_id="..."
export TF_VAR_jamfplatform_client_secret="..."
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

## Step 1: Categories

Categories group resources in Jamf Pro (policies, scripts, packages) for
reporting and Self Service organisation. They depend on no other Jamf Pro
resource, which makes them the right first thing to declare.

Open `categories.tf` and replace its contents with:

```hcl
resource "jamfplatform_pro_category" "engineering" {
  name     = "Engineering"
  priority = 9
}

resource "jamfplatform_pro_category" "operations" {
  name     = "Operations"
  priority = 9
}
```

**Key points:**

- Each `resource` block declares one object Terraform will create. The block
  address is `<type>.<name>`: `jamfplatform_pro_category.engineering` and
  `jamfplatform_pro_category.operations`. Terraform tracks each one in state.
- To reference one of these categories from another resource, use
  `jamfplatform_pro_category.engineering.id`. Terraform substitutes the API-assigned
  ID at plan time, so you never look up or hard-code an ID.
- `priority` is required and must be between 1 and 20. Lower values sort first
  in Jamf Pro.

Run a plan:

```bash
terraform plan
```

You should see `Plan: 2 to add`. Pass `-parallelism=1` on `apply`, because the
Jamf Pro API can be unreliable under concurrent load.

Apply:

```bash
terraform apply -parallelism=1
```

Type `yes` when prompted. Terraform creates both categories in Jamf Pro and
records their API-assigned IDs in `terraform.tfstate`. Open Jamf Pro and
confirm they appear under **Settings → Global → Categories**.

---

## Step 2: Scripts

Scripts live at **Settings → Computer Management → Scripts** in Jamf Pro. This
step introduces two things: reading a file from disk with `file()`, and
referencing a resource defined in another file.

The script file `support_files/scripts/hello_world.sh` is already in the repo.

Open `scripts.tf` and replace its contents with:

```hcl
resource "jamfplatform_pro_script" "hello_world" {
  name            = "Hello World"
  script_contents = file("${path.root}/support_files/scripts/hello_world.sh")
  category_id     = jamfplatform_pro_category.engineering.id
  priority        = "AFTER"
}
```

**Key points:**

- `file("${path.root}/support_files/scripts/hello_world.sh")` reads the
  script from disk at plan time and passes the contents as a string.
  `${path.root}` resolves to the directory you invoked Terraform from, which
  in this project is the repo root.
- `category_id = jamfplatform_pro_category.engineering.id` is a resource reference.
  Terraform reads the `id` attribute of the category and substitutes it here.
  Because this is a reference, Terraform knows the category must exist before
  the script, so you never specify ordering yourself.
- `priority = "AFTER"` controls when the script runs relative to other
  policy payloads: `"BEFORE"`, `"AFTER"`, or `"AT_REBOOT"`.

```bash
terraform plan
terraform apply -parallelism=1
```

Plan should show `1 to add`. Verify the script appears in Jamf Pro under
**Settings → Computer Management → Scripts**, assigned to the **Engineering**
category.

---

## Step 3: Static Computer Groups

Static computer groups depend on nothing else. They are a named container
whose membership you manage in the Jamf Pro UI or through MDM scope.
Useful for test scoping: add your test machines, then target the group in
a policy.

Open `static_computer_groups.tf` and replace its contents with:

```hcl
resource "jamfplatform_device_group" "test_machines" {
  name        = "Test Machines"
  group_type  = "static"
  device_type = "computer"
}
```

```bash
terraform plan
terraform apply -parallelism=1
```

After apply, open Jamf Pro under **Computers → Computer Groups** and add your
test machines to the group yourself. Terraform manages the group definition,
not its membership.

---

## Step 4: Policies

A policy ties everything together, referencing a category, a static group and
a script. This step shows how resource references compose: Terraform builds a
dependency graph from the references you write and creates the resources in
the right order.

Open `policies.tf` and replace its contents with:

```hcl
resource "jamfplatform_pro_policy" "run_hello_world" {
  general = {
    name            = "Run Hello World"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.engineering.id
  }

  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.test_machines.jamf_pro_id]
    }
  }

  scripts = {
    scripts = [
      {
        id       = jamfplatform_pro_script.hello_world.id
        priority = "After"
      }
    ]
  }

  maintenance = {
    update_inventory = true
  }
}
```

**Key points:**

- `category_id`, `computer_group_ids`, and `scripts[*].id` each reference a
  resource defined in a different file. Terraform resolves these at plan time,
  so you order nothing by hand.
- `computer_group_ids` uses `.jamf_pro_id` (the classic numeric Jamf Pro ID)
  rather than `.id` (which is a Platform Services UUID). The policy API requires
  the numeric ID.
- `computer_group_ids = [...]` takes a list. Even when scoping to one group,
  wrap the reference in `[...]`.
- `maintenance = { update_inventory = true }` runs an inventory update after
  the policy completes.

```bash
terraform plan
terraform apply -parallelism=1
```

Plan should show `1 to add`. Verify the policy appears in Jamf Pro under
**Computers → Policies**, scoped to **Test Machines** and carrying the
**Hello World** script.

---

## Drift: when Jamf Pro and Terraform disagree

Terraform's state file records the last-known configuration of every resource
it manages. If someone edits a resource in the Jamf Pro UI, the live
configuration diverges from state. Running `terraform plan` surfaces it:
Terraform reads the current state of each resource from the API and compares
it against the HCL. The HCL stays the source of truth.

### Change 1: editing a category name

In Jamf Pro, go to **Settings → Global → Categories**, find **Engineering**,
and rename it to something else.

Run a plan:

```bash
terraform plan
```

Terraform shows a modification:

```text
~ jamfplatform_pro_category.engineering
    ~ name = "Engineering (Test)" -> "Engineering"
```

The `~` symbol means an in-place update. Terraform intends to revert the name
back to `"Engineering"` as declared in `categories.tf`. Running
`terraform apply -parallelism=1` does that.

If you want to keep the new name instead, update `name` in `categories.tf` to
match, then re-run `terraform plan`. The plan should show no changes.

### Change 2: deleting and recreating a category

This one does more damage. In Jamf Pro, delete **Engineering**, then create a
new category with the same name.

Run a plan:

```bash
terraform plan
```

Terraform shows:

```text
+ jamfplatform_pro_category.engineering
~ jamfplatform_pro_policy.run_hello_world
~ jamfplatform_pro_script.hello_world
```

The `+` means Terraform intends to create the resource. Terraform tracks
resources by their API-assigned numeric ID, recorded in state. That ID no
longer exists, because the category was deleted, so Terraform reads the
resource as missing and plans to recreate it. The script and the policy show
`~` alongside it: both reference the category, so their `category_id` has to
move to whatever ID the new category gets.

The new **Engineering** category you made by hand carries a different ID and
is invisible to Terraform. If you run `terraform apply -parallelism=1`,
Terraform attempts to create a new **Engineering** category through the API,
and Jamf Pro rejects it with a duplicate name error. The apply fails.

This is why splitting control between Terraform and the UI breaks things.
Terraform owns state; the UI owns the live instance; they are now out of sync
and neither can fully reconcile without manual intervention.

**The fix:** remove the stale state entry, then import the hand-made resource
at its current ID:

```bash
terraform state rm jamfplatform_pro_category.engineering
```

Then add an import block in `imports.tf` pointing to the new ID (find it with
`jamf-cli pro categories list -o table`), and apply:

```bash
terraform apply -parallelism=1
```

This keeps the existing resource and its ID, so anything in Jamf Pro already
referencing that category stays intact. Deleting the hand-made copy and
recreating it through Terraform would assign a new ID and break those
references.

The next section covers the full import workflow: how to write the import
block, run `-generate-config-out`, and verify a clean result.

---

## Importing existing resources

Import brings a resource that already exists in Jamf Pro under Terraform
management without recreating it. This is the path for resources created
by hand in the UI before you brought Terraform in, or for resources orphaned
by the delete/recreate scenario above.

The workflow uses an `import` block alongside `terraform plan -generate-config-out`,
which reads the live resource from the API and generates the HCL for you.

**Before you start:** create two unmanaged resources to simulate configuration
that exists in Jamf Pro outside of Terraform. Use whichever approach you prefer:

- **Jamf Pro UI.** Create a category named **Finance** under
  **Settings → Global → Categories → New**, and a script named
  **Inventory Update** under **Settings → Computer Management → Scripts → New**.
- **jamf-cli.** A good opportunity to see API-driven config creation before
  Terraform is in the picture:

```bash
echo '{"name":"Finance","priority":9}' | jamf-cli pro categories create

echo '{"name":"Inventory Update","scriptContents":"#!/bin/bash\necho recon","priority":"AFTER"}' | jamf-cli pro scripts create
```

Then find their numeric IDs:

```bash
jamf-cli pro categories list -o table
jamf-cli pro scripts list -o table
```

Note the `id` value for each. You use them in the import blocks.

### Import 1: a category

Open `imports.tf` and uncomment the category block, filling in the ID:

```hcl
import {
  provider = jamfplatform
  to       = jamfplatform_pro_category.finance
  id       = "42" # replace with the actual numeric ID from Jamf Pro
}
```

Include `provider = jamfplatform`. Terraform works out which provider serves a
resource type from the block that declares it, and no block declares
`jamfplatform_pro_category.finance` yet. That is what you are about to
generate. Without the argument, Terraform guesses `hashicorp/jamfplatform` and
fails with `unavailable provider`.

Run plan with config generation:

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform reads the live category from the API and writes its full resource
block to `generated.tf`. Open it and review the output, which looks something
like this:

```hcl
resource "jamfplatform_pro_category" "finance" {
  name     = "Finance"
  priority = 9
  timeouts = null
}
```

Copy the **whole** generated block into `categories.tf` and delete
`generated.tf`. Leave the import block in `imports.tf` for now, but **remove
its `provider` argument**. The target has a resource block now, and Terraform
rejects the argument on an import block whose target is already configured:
`Invalid import provider argument`.

Copy the generated block as-is; any attributes you drop will show as drift on
the next plan.

Run apply to perform the import. Import blocks execute on apply, not plan:
`-generate-config-out` reads the API and writes HCL without touching state.

```bash
terraform apply -parallelism=1
```

Once apply completes, delete the import block from `imports.tf`.

Run a final plan to confirm Terraform sees no changes:

```bash
terraform plan
```

A clean plan (`No changes`) means **Finance** is under Terraform management.
Future changes go through the HCL, and an edit in the UI shows as drift on the
next plan.

### Import 2: a script

Uncomment the script block in `imports.tf`, filling in the ID:

```hcl
import {
  provider = jamfplatform
  to       = jamfplatform_pro_script.inventory_update
  id       = "17" # replace with the actual numeric ID from Jamf Pro
}
```

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform generates the script resource block with `script_contents` inline,
the whole script body embedded as a string in the HCL. For anything beyond a
trivial script that is unreadable and hard to maintain.

This is one of the limitations of `generate-config-out`: it knows nothing about
which attributes belong in external files, so you extract them yourself. Save
the script body to
`support_files/scripts/inventory_update.sh` and replace the inline value in
`generated.tf` with:

```hcl
script_contents = file("${path.root}/support_files/scripts/inventory_update.sh")
```

> **This is the problem jamformer solves.** Reading an existing Jamf Pro
> instance, jamformer spots attributes like `script_contents` and `payloads`
> that carry file bodies and extracts them into `support_files/`. The HCL comes
> out readable, with file references already in place.

Copy the **whole** block into `scripts.tf` and delete `generated.tf`. Leave
the import block in `imports.tf` for now, again removing its `provider`
argument.

Run apply to perform the import:

```bash
terraform apply -parallelism=1
```

Once apply completes, delete the import block from `imports.tf`.

Run a final plan to verify a clean result:

```bash
terraform plan
```

---

## Discovering resources with jamformer

The import workflow above works for one or two resources by hand. It does not
scale to a Jamf Pro instance holding hundreds of policies, profiles and groups.
jamformer reads the whole instance and generates Terraform configuration in one
pass.

Create a few more resources in your sandbox through the Jamf Pro UI or
`jamf-cli`: a couple of categories, a script and a static group. Then run
jamformer against the instance.

jamformer runs interactively. Follow its prompts, point it at your sandbox, and
let it write output into a local directory.

**What to look for in the output:**

- **Per-resource-type files** (`categories.tf`, `scripts.tf`, and so on),
  following the same naming convention as this project. Copy the generated
  files straight into your own `.tf` files.
- **`support_files/`**, holding the script bodies, profile payloads and other
  file content that jamformer pulls out into separate files, with `file()`
  references left behind in the HCL. Compare that to the inline
  `script_contents` you saw from `generate-config-out`.
- **`_import.tf` files**. jamformer writes import blocks alongside each
  resource file. Use them the same way as `imports.tf` in this project: add
  the block, run `terraform plan`, verify a clean result, then remove the
  import block.

This project borrows jamformer's file naming and `support_files/` layout on
purpose, so moving a jamformer export into a structured project is a copy
rather than a rewrite.

---

## Cleaning up

To remove everything Terraform created in your sandbox:

```bash
terraform destroy -parallelism=1
```

Terraform reads state and deletes each resource from Jamf Pro. Type `yes`
when prompted. The state file will be empty when it finishes.

Then delete the integration in [account.jamf.com](https://account.jamf.com)
under **Integrations** to clean up credentials.

---

## What's next

- **`ref-jamfplatform-starter` branch**, the companion starter for native
  Platform API resources (blueprints, compliance benchmarks, device groups).
  It covers the same flat project layout as this branch, against Platform
  Services resources rather than Jamf Pro parity resources.
- **`ref-jamfpro` branch**, the next step up. It uses `environments/` and
  `modules/` structure that scales to several Jamf Pro tenants from one set of
  resource definitions, which is what a jamformer export refactors into. Its
  *Graduating to remote state* section covers remote state, for when you
  collaborate or move beyond a single machine.
- **[Resources for getting started with Terraform and Jamf](https://concepts.jamf.com/guides/infrastructure-as-code/resources-for-getting-started-with-terraform-and-jamf/)**,
  curated reading for Jamf admins new to IaC.
