# Contributing

Thanks for helping improve this Terraform configuration for the Jamf Platform.

This repo uses Terraform modules to create Jamf Pro and Jamf Security Cloud objects.

## Quick start

- Make your change.
- Run formatting checks.
- Open a Pull Request and fill out the PR template.

```sh
terraform fmt -check -recursive
```

## Repository layout

- `main.tf`, `providers.tf`, `variables.tf`, `outputs.tf`: root module wiring and "include_..." toggles.
- `modules/`: reusable sub-modules (each should be runnable via provider aliases).
- `examples/`: example usage patterns and module examples.
- `testing/`: local-only helpers (see `testing/README.md`).
- `spec.yml`: the "feature toggle" catalog used by CI to apply each boolean option.

## Development workflow

### Keep secrets and state out of PRs

This repo's `.gitignore` is intended to exclude Terraform state and tfvars files. Before opening a PR, verify you are not including any of the following:

- Terraform state: `*.tfstate`, `*.tfstate.backup`, `.terraform/`
- Local variables: `terraform.tfvars`, `terraform.*.tfvars`
- Local Terraform CLI config: `*.terraformrc`

If you use `testing/test.tfvars` for local iteration, keep it uncommitted.

### Formatting (required)

CI checks Terraform formatting.

```sh
terraform fmt -check -recursive
```

### Provider aliases (how modules are intended to be used)

Modules under `modules/` generally expect aliased providers and should declare `configuration_aliases` in their `terraform { required_providers { ... } }` blocks.

If you add a new module or expand provider usage, ensure:

- The module uses provider aliases (e.g., `jamfpro.jpro`, `jsc.jsc`).
- The root module passes those aliases via a `providers = { ... }` block.

Example module call with provider aliases:

```terraform
module "some-module" {

  source = "./modules/some-module"
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}
```

### Adding or changing a module

If you change module behavior or add a new module, please also:

- Include or update a module `README.md` describing what it creates and what it requires.
- Add an example under `examples/` (the PR template expects this for module changes).
- Keep any artifacts (mobileconfig, scripts, templates) inside the module's `support_files/` directory.

### Updating `spec.yml`

`spec.yml` is used by CI to iterate through boolean "include" options.

If your change adds a new toggle / option:

- Add the `options:` entry in `spec.yml`.
- Keep the key consistent with the variable name in `variables.tf`.
- Include `module_name`, `required_provider`, `display_name`, and `display_desc` so the option is discoverable and testable.

### CI expectations

Workflows on PRs/`main` enforce formatting and (in some workflows) apply/destroy patterns in a staging environment.

To keep PRs reviewable and safe:

- Prefer small, focused changes.
- Keep modules idempotent (a second apply should be a no-op).
- Avoid changes that require interactive input.

## Getting help

If you're unsure where a change belongs (root vs module), open a draft PR and describe your intent - maintainers can help steer structure and module boundaries.
