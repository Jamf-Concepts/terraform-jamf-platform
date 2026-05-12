# Getting started with Terraform and Jamf Pro

> **You are on the `ref-jamfpro-starter` branch.** This is a sandbox companion
> for the Jamf IaC Enablement session. Other branches in this repository are
> unrelated.

A flat Terraform project that manages four Jamf Pro resource types against a
sandbox instance. Flat means all `.tf` files sit at the root — no
`environments/` folders, no modules. This is the same layout that
[jamformer](https://github.com/Jamf-Concepts/jamformer) produces when it reads
an existing Jamf Pro instance, and the right starting point before adding
multi-environment structure.

---

## Learning outcomes

By the end of this session you will be able to:

- Configure the Jamf Pro Terraform provider with OAuth2 credentials
- Declare resources, understand state, and run `init`, `plan`, `apply`, and `destroy`
- Reference resource IDs across files and let Terraform resolve dependency ordering automatically
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
| `policies.tf` | Policy | Composing resources — category, group, and script referenced in one block |

---

## Prerequisites

- A Jamf Pro sandbox instance — **do not use production**
- Terraform >= 1.11.0 (see below)
- VS Code with the HashiCorp Terraform extension (see below)
- jamf-cli (see below)
- jamformer (see below)
- An API Role and Client in the sandbox (see below)

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

### Install and configure jamf-cli

[jamf-cli](https://github.com/Jamf-Concepts/jamf-cli) is used during the
import exercise to look up numeric resource IDs from Jamf Pro. Install it via
Homebrew:

```bash
brew install Jamf-Concepts/tap/jamf-cli
```

Then configure it against your sandbox instance:

```bash
jamf-cli pro setup
```

Follow the prompts to enter your Jamf Pro URL and local admin credentials.
jamf-cli creates an API client automatically.

### Install jamformer

[jamformer](https://github.com/Jamf-Concepts/jamformer) reads an existing Jamf
Pro instance and generates Terraform configuration from it. It is used later
in this session to demonstrate how to bootstrap a project from existing
resources at scale.

```bash
brew install Jamf-Concepts/tap/jamformer
```

### Create an API Role and Client

Terraform authenticates to Jamf Pro using OAuth2. Use jamf-cli to create the
credentials from the command line:

Create a role with all privileges — appropriate for learning, tighten for
production:

```bash
jamf-cli pro api-roles-privileges api-role-privileges -o json | \
  jq '{displayName: "terraform-starter", privileges: .privileges}' | \
  jamf-cli pro api-roles create
```

Create a client and attach the role:

```bash
echo '{"displayName":"terraform-starter","enabled":true,"accessTokenLifetimeSeconds":300,"authorizationScopes":["terraform-starter"]}' | \
  jamf-cli pro api-integrations create
```

Retrieve credentials — copy immediately, the secret is shown only once:

```bash
jamf-cli pro api-integrations client-credentials --name "terraform-starter"
```

If you have multiple jamf-cli profiles, add `-p <profile-name>` to each
command. `client-credentials` rotates the secret — running it again invalidates
the previous one.

Copy the `clientId` and `clientSecret` values — you'll need them in the next
step.

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

Open `terraform.tfvars` and fill in your sandbox URL with the `clientId` and
`clientSecret` from the previous step:

```hcl
jamfpro_instance_fqdn = "https://yourcompany.jamfcloud.com"
jamfpro_client_id     = "your-client-id"
jamfpro_client_secret = "your-client-secret"
```

`terraform.tfvars` is gitignored — it will never be committed.

Alternatively, export credentials as environment variables:

```bash
export TF_VAR_jamfpro_instance_fqdn="https://yourcompany.jamfcloud.com"
export TF_VAR_jamfpro_client_id="..."
export TF_VAR_jamfpro_client_secret="..."
```

### Initialise Terraform

```bash
terraform init
```

Terraform downloads the `deploymenttheory/jamfpro` provider from the registry
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

Categories group resources in Jamf Pro — policies, scripts, packages — for
reporting and Self Service organisation. They have no dependencies on other
Jamf Pro resources, which makes them the right first thing to declare.

Open `categories.tf` and replace its contents with:

```hcl
resource "jamfpro_category" "engineering" {
  name = "Engineering"
}

resource "jamfpro_category" "operations" {
  name = "Operations"
}
```

**Key points:**

- Each `resource` block declares one object Terraform will create. The block
  address is `<type>.<name>` — `jamfpro_category.engineering` and
  `jamfpro_category.operations`. Terraform tracks them independently in state.
- To reference one of these categories from another resource, use
  `jamfpro_category.engineering.id`. Terraform substitutes the API-assigned
  ID at plan time — you never look up or hard-code IDs manually.

Run a plan:

```bash
terraform plan
```

You should see `Plan: 2 to add`. The `-parallelism=1` flag is required on
`apply` — the Jamf Pro API can be unreliable under concurrent load.

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
resource "jamfpro_script" "hello_world" {
  name            = "Hello World"
  script_contents = file("${path.root}/support_files/scripts/hello_world.sh")
  category_id     = jamfpro_category.engineering.id
  priority        = "AFTER"
}
```

**Key points:**

- `file("${path.root}/support_files/scripts/hello_world.sh")` reads the
  script from disk at plan time and passes the contents as a string.
  `${path.root}` resolves to the directory Terraform was invoked from — in
  this project, the repo root.
- `category_id = jamfpro_category.engineering.id` is a resource reference.
  Terraform reads the `id` attribute of the category and substitutes it here.
  Because this is a reference, Terraform knows the category must exist before
  the script — you never specify ordering manually.
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

Static computer groups have no resource dependencies — they are a named
container whose membership you manage in the Jamf Pro UI or via MDM scope.
Useful for test scoping: add your test machines, then target the group in
a policy.

Open `static_computer_groups.tf` and replace its contents with:

```hcl
resource "jamfpro_static_computer_group" "test_machines" {
  name = "Test Machines"
}
```

```bash
terraform plan
terraform apply -parallelism=1
```

After apply, open Jamf Pro under **Computers → Computer Groups** and add your
test machine(s) to the group manually. Terraform manages the group definition,
not its membership.

---

## Step 4: Policies

A policy ties everything together — it references a category, a static group,
and a script. This step shows how resource references compose: Terraform builds
a dependency graph from the references you write and creates resources in the
correct order automatically.

Open `policies.tf` and replace its contents with:

```hcl
resource "jamfpro_policy" "run_hello_world" {
  name            = "Run Hello World"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.engineering.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_static_computer_group.test_machines.id]
  }

  payloads {
    scripts {
      id       = jamfpro_script.hello_world.id
      priority = "After"
    }
    maintenance {
      recon = true
    }
  }
}
```

**Key points:**

- `category_id`, `computer_group_ids`, and `scripts.id` each reference a
  resource defined in a different file. Terraform resolves these at plan time —
  no manual ordering required.
- `computer_group_ids = [...]` takes a list. Even when scoping to one group,
  wrap the reference in `[...]`.
- `maintenance { recon = true }` runs an inventory update after the policy
  completes.

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
it manages. If someone edits a resource directly in the Jamf Pro UI, the live
configuration diverges from state. Running `terraform plan` detects this —
Terraform reads the current state of each resource from the API and compares
it against the HCL. The HCL is always the source of truth.

### Change 1: editing a category name

In Jamf Pro, go to **Settings → Global → Categories**, find **Engineering**,
and rename it to something else.

Run a plan:

```bash
terraform plan
```

Terraform shows a modification:

```text
~ jamfpro_category.engineering
    ~ name = "Engineering (Test)" -> "Engineering"
```

The `~` symbol means an in-place update. Terraform intends to revert the name
back to `"Engineering"` as declared in `categories.tf`. Running
`terraform apply -parallelism=1` does exactly that.

If you want to keep the new name instead, update `name` in `categories.tf` to
match, then re-run `terraform plan` — the plan should show no changes.

### Change 2: deleting and recreating a category

This is more damaging. In Jamf Pro, delete **Engineering** entirely, then
create a new category with the same name.

Run a plan:

```bash
terraform plan
```

Terraform shows:

```text
+ jamfpro_category.engineering
```

The `+` means Terraform intends to create the resource. What happened:
Terraform tracks resources by their API-assigned numeric ID, recorded in
state. That ID no longer exists — the category was deleted. Terraform
concludes the resource is missing and plans to recreate it.

The new **Engineering** category you created manually has a different ID and
is invisible to Terraform. If you run `terraform apply -parallelism=1`,
Terraform attempts to create a new **Engineering** category via the API —
and Jamf Pro rejects it with a duplicate name error. The apply fails.

This is why splitting control between Terraform and the UI breaks things.
Terraform owns state; the UI owns the live instance; they are now out of sync
and neither can fully reconcile without manual intervention.

**The fix:** remove the stale state entry, then import the manually-created
resource at its current ID:

```bash
terraform state rm jamfpro_category.engineering
```

Then add an import block in `imports.tf` pointing to the new ID (find it with
`jamf-cli pro categories list -o table`), and apply:

```bash
terraform apply -parallelism=1
```

This preserves the existing resource and its ID — anything in Jamf Pro already
referencing that category stays intact. Deleting the manual copy and
recreating via Terraform would assign a new ID and break those references.

The full import workflow — how to write the import block, run
`-generate-config-out`, and verify a clean result — is covered in the next
section.

---

## Importing existing resources

Import brings a resource that already exists in Jamf Pro under Terraform
management without recreating it. This is the path for resources created
manually in the UI before Terraform was involved — or for resources orphaned
by the delete/recreate scenario above.

The workflow uses an `import` block alongside `terraform plan -generate-config-out`,
which reads the live resource from the API and generates the HCL for you.

**Before you start:** create two unmanaged resources to simulate configuration
that exists in Jamf Pro outside of Terraform. Use whichever approach you prefer:

- **Jamf Pro UI** — create a category named **Finance** under
  **Settings → Global → Categories → New**, and a script named
  **Inventory Update** under **Settings → Computer Management → Scripts → New**.
- **jamf-cli** — a good opportunity to see API-driven config creation before
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

Note the `id` value for each — you'll use them in the import blocks.

### Import 1: a category

Open `imports.tf` and uncomment the category block, filling in the ID:

```hcl
import {
  to = jamfpro_category.finance
  id = "42"  # replace with the actual numeric ID from Jamf Pro
}
```

Run plan with config generation:

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform reads the live category from the API and writes its full resource
block to `generated.tf`. Open it and review the output — it will look
something like:

```hcl
resource "jamfpro_category" "finance" {
  name = "Finance"
}
```

Copy the resource block into `categories.tf`. Delete the import block from
`imports.tf` and delete `generated.tf`.

Run a final plan to confirm Terraform sees no changes:

```bash
terraform plan
```

A clean plan (`No changes`) means **Finance** is now fully under Terraform
management. Any future changes must go through HCL — edits in the UI will
show as drift on the next plan.

### Import 2: a script

Uncomment the script block in `imports.tf`, filling in the ID:

```hcl
import {
  to = jamfpro_script.inventory_update
  id = "17"  # replace with the actual numeric ID from Jamf Pro
}
```

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform generates the script resource block with `script_contents` inline —
the entire script body embedded as a string directly in the HCL. For anything
beyond a trivial script this is unreadable and hard to maintain.

This is one of the limitations of `generate-config-out`: it has no awareness
of which attributes are better expressed as external files. You have to
extract them manually. Save the script body to
`support_files/scripts/inventory_update.sh` and replace the inline value in
`generated.tf` with:

```hcl
script_contents = file("${path.root}/support_files/scripts/inventory_update.sh")
```

> **This is exactly the problem jamformer solves.** When jamformer generates
> configuration from an existing Jamf Pro instance, it detects attributes like
> `script_contents` and `payloads` that contain file bodies and extracts them
> automatically into `support_files/`. The result is immediately readable HCL
> with proper file references — no manual extraction required.

Copy the block into `scripts.tf`, delete the import block from `imports.tf`
and delete `generated.tf`, then run `terraform plan` to verify
a clean result.

---

## Discovering resources with jamformer

The manual import workflow above works for one or two resources. For a real
Jamf Pro instance with hundreds of policies, profiles, and groups, it does not
scale. jamformer solves this — it reads the entire instance and generates
Terraform configuration in one pass.

Create a handful of additional resources in your sandbox — categories, a
script, a static group — using the Jamf Pro UI or `jamf-cli`. Then run
jamformer against the instance.

jamformer is designed to be run interactively. Follow its prompts, point it at
your sandbox, and let it generate output into a local directory.

**What to look for in the output:**

- **Per-resource-type files** (`categories.tf`, `scripts.tf`, etc.) — same
  naming convention as this project. The generated files can be copied
  directly into your `.tf` files.
- **`support_files/`** — script bodies, profile payloads, and other file
  content are extracted automatically into separate files with `file()`
  references in the HCL. Compare this to the inline `script_contents` you saw
  with `generate-config-out`.
- **`_import.tf` files** — jamformer generates import blocks alongside each
  resource file. Use these the same way as `imports.tf` in this project: add
  the block, run `terraform plan`, verify a clean result, then
  remove the import block.

The file naming conventions and `support_files/` layout in this project are
intentionally aligned with jamformer's output so that moving from a jamformer
export into a structured project is a copy, not a rewrite.

---

## Cleaning up

To remove everything Terraform created in your sandbox:

```bash
terraform destroy -parallelism=1
```

Terraform reads state and deletes each resource from Jamf Pro. Type `yes`
when prompted. The state file will be empty when it finishes.

Then delete the API client and role created during setup:

```bash
jamf-cli pro api-integrations delete --name "terraform-starter" --yes
jamf-cli pro api-roles delete --name "terraform-starter" --yes
```

---

## What's next

- **`ref-jamfpro` branch** — the next step up. Uses `environments/` +
  `modules/` structure that scales to multiple Jamf Pro tenants from a single
  set of resource definitions. This is what a jamformer export refactors into.
  It also covers remote state — when you are ready to collaborate or move
  beyond a single machine, see its *Graduating to remote state* section.
- **[Resources for getting started with Terraform and Jamf](https://concepts.jamf.com/guides/infrastructure-as-code/resources-for-getting-started-with-terraform-and-jamf/)** — curated reading for Jamf admins new to IaC.
