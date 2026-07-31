# Contributing

Thanks for your interest in contributing. This branch is a reference for
managed service providers and anyone running Jamf configuration as code across
more than one tenant — keep that audience in mind when proposing changes.

## What this project is and is not

**It is** a worked example of a multi-tenant Terraform pipeline, sanitised from
a production system, structured so someone can read it top to bottom and
recognise both the Jamf resources and the operational scaffolding around them.

**It is not** a module published for direct consumption, nor a turnkey
configuration. Users are expected to fork it and adapt it to their own service.

Changes that make the patterns clearer, more honest about their trade-offs, or
more portable are welcome. Changes that add abstraction or indirection for its
own sake, or that reintroduce organisation-specific detail, will likely be
declined.

## Reporting issues

Open a GitHub issue with:

- The Terraform version (`terraform -version`)
- The provider versions in use
- The exact command or workflow that failed, and the full output with
  credentials redacted
- A minimal HCL snippet or workflow excerpt that reproduces it

Provider bugs belong on the provider repositories rather than here:

- [Jamf-Concepts/terraform-provider-jamfprotect](https://github.com/Jamf-Concepts/terraform-provider-jamfprotect)
- [deploymenttheory/terraform-provider-jamfpro](https://github.com/deploymenttheory/terraform-provider-jamfpro)

## Proposing changes

1. Fork the repository.
2. Branch off `ref-jamfprotect-msp`. Note this is an **orphaned** branch with no
   shared history with `main` — do not merge across branches in this repository.
3. Make your changes.
4. Run the checks below.
5. Apply your changes against a sandbox tenant you own to confirm they work end
   to end. Never test against a production or customer instance.
6. Open a pull request describing what changed, why, and what you tested it
   against.

### Before you commit

```bash
# From the repository root
terraform fmt -recursive
tflint --recursive --config .tflint.hcl

# Per workspace
terraform -chdir=customers/staging init -backend=false
terraform -chdir=customers/staging validate

# Scripts
bash -n scripts/*.sh
shellcheck -S warning scripts/*.sh
```

The plan workflow runs `fmt -check`, `tflint` and `validate`, so anything the
commands above catch will fail CI anyway.

## Style and conventions

- **One file per resource type or logical area** in the module, named after the
  concept as it appears in the Jamf Protect console (`plans.tf`,
  `exception_sets.tf`, `device_controls.tf`).
- **Conditional resources** use `count` on a flag derived in `locals`, not an
  inline tier comparison repeated in every resource.
- **Dynamic per-customer resources** use `for_each` over a map declared in the
  customer's tfvars. Do not flatten dissimilar resources into one parameterised
  `for_each` purely for the sake of DRY.
- **Comments explain the reasoning, not the syntax.** Why `depends_on` is
  needed, why `-parallelism=1` is mandatory, why a filter exists, what a
  trade-off costs. A comment restating what the next line plainly says is
  noise.
- **Document trade-offs where they occur.** Several decisions in here are
  defensible rather than correct — providers configured inside the module,
  credentials written to a run summary, an unpinned lock file. Each is
  explained at the point it happens. Keep that up rather than quietly
  smoothing it over.
- **Sensitive values** are `sensitive = true` on the variable, never given a
  default, and never committed. Anything genuinely secret reaches Terraform as
  a `TF_VAR_*` environment variable from a GitHub Environment secret.
- **Workflows** declare explicit least-privilege `permissions`, pin third-party
  actions by commit SHA, and validate any user input before it reaches a shell
  or an S3 key.

## Nothing organisation-specific

This branch is intended to be shareable. Pull requests must not introduce:

- Real email addresses, usernames, team names or GitHub handles
- Real tenant URLs, bucket names, account IDs or webhook URLs
- Customer names, or exclusions traceable to a specific customer or migration
- Links to internal documentation, ticketing or wiki systems
- Dependencies on internal infrastructure

Where a value has to exist, make it a repository variable or an environment
variable with a documented placeholder — and pick a placeholder that fails
loudly rather than one that looks plausible.

## Provider version policy

Constraints in `modules/protect-baseline/main.tf` use `>= X.Y.Z` with the
minimum tested version, and `.terraform.lock.hcl` is gitignored, so
contributors run `terraform init -upgrade` to pull the latest satisfying
version. This trades reproducibility for currency in a fast-moving provider
ecosystem.

When proposing a constraint bump, confirm the new minimum works against a
sandbox tenant and note which feature or fix motivated it.

## Scope

In scope:

- Jamf Protect resources via `Jamf-Concepts/jamfprotect`
- Jamf Pro resources via `Jamf-Concepts/jamfplatform`, where they support the
  Protect deployment
- The pipeline, the scripts, and the documentation around both

Out of scope:

- General Terraform tutorials
- Prescriptive CI/CD or remote state architecture beyond what is documented —
  this repository documents one approach rather than recommending it over others
- Other Jamf products, which have their own providers and belong on their own
  reference branches

## Licence

By contributing, you agree that your contributions will be licensed under the
terms of the repository's [LICENSE](LICENSE.md) (MIT).
