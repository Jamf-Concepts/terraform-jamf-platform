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
- An API Role and Client in the sandbox (see below)
- jamf-cli (see below)

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

### Create an API Role and Client in Jamf Pro

Terraform authenticates to Jamf Pro using OAuth2. Before running this project,
create credentials in your sandbox instance:

1. Go to **Settings → System → API roles and clients → API Roles**.
2. Create a role. Use **All** privileges while learning — tighten later.
3. Go to **API roles and clients → API Clients**.
4. Create a client, attach the role, and click **Generate client secret**.
5. Copy the **Client ID** and **Client Secret** — you'll need them in the next step.
   The secret is shown only once.

---

## Setup

### 1. Clone

```bash
git clone --branch ref-jamfpro-starter --single-branch https://github.com/Jamf-Concepts/terraform-jamf-platform.git
cd terraform-jamf-platform
```

### 2. Configure credentials

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in your sandbox URL and API client credentials:

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

### 3. Initialise Terraform

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
terraform plan -parallelism=1
```

You should see `Plan: 2 to add`. The `-parallelism=1` flag is required for
all plan and apply commands — the Jamf Pro API rate-limits concurrent requests.

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
terraform plan -parallelism=1
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
terraform plan -parallelism=1
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
terraform plan -parallelism=1
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
terraform plan -parallelism=1
```

Terraform shows a modification:

```text
~ jamfpro_category.engineering
    ~ name = "Engineering (Test)" -> "Engineering"
```

The `~` symbol means an in-place update. Terraform intends to revert the name
back to `"Engineering"` as declared in `categories.tf`. Running
`terraform apply` does exactly that.

If you want to keep the new name instead, update `name` in `categories.tf` to
match, then re-run `terraform plan` — the plan should show no changes.

### Change 2: deleting and recreating a category

This is more damaging. In Jamf Pro, delete **Engineering** entirely, then
create a new category with the same name.

Run a plan:

```bash
terraform plan -parallelism=1
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
is invisible to Terraform. If you run `terraform apply`, Terraform creates
another **Engineering** category alongside the unmanaged one.

**The fix:** run `terraform apply` to let Terraform recreate the resource with
the correct ID, then delete the manually-created duplicate from the Jamf Pro
UI. Or import the manually-created resource — see the next section.

---

## Importing existing resources

Import brings a resource that already exists in Jamf Pro under Terraform
management without recreating it. This is the path for resources created
manually in the UI before Terraform was involved — or for resources orphaned
by the delete/recreate scenario above.

The workflow uses an `import` block alongside `terraform plan -generate-config-out`,
which reads the live resource from the API and generates the HCL for you.

**Before you start:** create two unmanaged resources using `jamf-cli` — these
simulate resources that exist in Jamf Pro outside of Terraform:

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
terraform plan -parallelism=1 -generate-config-out=generated.tf
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
terraform plan -parallelism=1
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
terraform plan -parallelism=1 -generate-config-out=generated.tf
```

Terraform generates the script resource block with `script_contents` inline.
If you prefer to keep the script body in a separate file (as in Step 2),
save the content to `support_files/scripts/inventory_update.sh` and replace
the inline value in `generated.tf` with:

```hcl
script_contents = file("${path.root}/support_files/scripts/inventory_update.sh")
```

Copy the block into `scripts.tf`, delete the import block from `imports.tf`
and delete `generated.tf`, then run `terraform plan -parallelism=1` to verify
a clean result.

---

## Cleaning up

To remove everything Terraform created in your sandbox:

```bash
terraform destroy -parallelism=1
```

Terraform reads state and deletes each resource from Jamf Pro. Type `yes`
when prompted. The state file will be empty when it finishes.

---

## What's next

- **jamformer** — run `jamformer` against your sandbox instance. Compare the
  output structure to this project: the file naming conventions and
  `support_files/` layout are intentionally aligned.
- **`ref-jamfpro` branch** — the next step up. Uses `environments/` +
  `modules/` structure that scales to multiple Jamf Pro tenants from a single
  set of resource definitions. This is what a jamformer export refactors into.
- **[Resources for getting started with Terraform and Jamf](https://concepts.jamf.com/guides/infrastructure-as-code/resources-for-getting-started-with-terraform-and-jamf/)** — curated reading for Jamf admins new to IaC.
