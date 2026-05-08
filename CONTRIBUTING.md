# Contributing

Thanks for your interest in contributing. This repository is a reference and
learning resource for Jamf administrators adopting Terraform — keep that
audience in mind when proposing changes.

## What this project is and is not

**It is** a worked example of managing Jamf Pro and Jamf Platform with
Terraform, structured so a Jamf admin new to Terraform can read it
top-to-bottom and recognise the resources being created.

**It is not** a Terraform module published for direct consumption, nor a
production-ready turnkey configuration. Customers are expected to fork or
copy this repo into their own workspace and modify it for their tenant.

Changes that align with the audience and goals are welcomed. Changes that
add abstraction, indirection, or assume Terraform expertise the audience
does not have will likely be declined.

## Reporting issues

Open a GitHub issue with:

- The Terraform version (`terraform -version`)
- The provider versions in your `.terraform.lock.hcl` if available
- The Jamf Pro version of your tenant
- The exact command you ran and the full error output (with credentials
  redacted)
- A minimal HCL snippet that reproduces the issue

Provider bugs in `deploymenttheory/jamfpro` or `Jamf-Concepts/jamfplatform`
should be reported on those provider repositories directly.

## Proposing changes

1. Fork the repository.
2. Create a branch off the default branch.
3. Make your changes. Run `terraform fmt -recursive` from the repo root and
   `terraform validate` from your environment folder before committing.
4. Apply your changes against a sandbox tenant to confirm they work
   end-to-end. Do not test against a production instance.
5. Open a pull request describing what changed, why, and what you tested
   against.

PRs that change resource definitions should include a short note in the
description explaining what the resource demonstrates and why it belongs in
the reference set.

## Style and conventions

- **One file per resource type or logical area**, named to match the Jamf
  Pro UI mental model (`smart_computer_groups.tf`, `policies.tf`, etc.).
  This matches jamformer's output convention.
- **`for_each` over a `locals` map** for resources that vary only in name
  or a small number of attributes.
- **Single resource blocks** for resources with unique configuration. Do not
  flatten dissimilar resources into one parameterised `for_each` just for
  DRY.
- **Comments explain Terraform concepts in context** for the audience —
  what `path.module` resolves to, why `parallelism=1` matters, what a
  `data` source does. Comments do not need to explain Jamf concepts.
- **Resource names** include `(Managed by Terraform)` so the resources are
  identifiable in the Jamf Pro UI.
- **Sensitive values** must be `sensitive = true` on the variable and never
  have a default value.

## Provider version policy

Provider version constraints in `modules/jamfpro/terraform.tf` use `>= X.Y.Z`
with the minimum tested version. The `.terraform.lock.hcl` is gitignored so
contributors and customers run `terraform init -upgrade` to pull the latest
version that satisfies the constraints. This trades reproducibility for
ease of staying current in a fast-moving provider ecosystem.

When proposing a constraint bump, confirm the new minimum works against a
sandbox tenant and note what feature or fix motivated the bump.

## Scope

In scope:

- Jamf Pro resources via `deploymenttheory/jamfpro`
- Jamf Platform resources via `Jamf-Concepts/jamfplatform`

Out of scope:

- Jamf Protect, Jamf Security Cloud, AxM (different providers and auth
  models)
- Jamf-managed CI/CD pipelines or remote state architecture (Jamf does not
  provide IaC consultancy; the README documents graduation paths but does
  not prescribe one)
- General Terraform tutorials

## Licence

By contributing, you agree that your contributions will be licensed under
the terms of the repository's [LICENSE](LICENSE.md) (MIT).
