# Style guide

This guide documents the conventions used in this repository for Terraform code and Jamf Platform module structure.

## Terraform standards

### Formatting

- Always run `terraform fmt` on changes.
- CI enforces `terraform fmt -check -recursive`.

### Naming

- Use `snake_case` for Terraform resource labels and variable names.
- Prefer descriptive resource labels (avoid overly generic names like `this`).
- Boolean toggles should use `include_...` naming (e.g., `include_mac_cis_lvl1_benchmark`).

Naming convention:

| What | Convention | Examples from this repo | Notes |
| --- | --- | --- | --- |
| Module folder names | `modules/<area>-<platform>-<purpose>` | `modules/compliance-iOS-cis-level-1`, `modules/configuration-jamf-pro-categories`, `modules/endpoint-security-macOS-microsoft-defender`, `modules/network-security-access-policy`, `modules/onboarder-management-macOS` | Use hyphens, keep platform casing consistent (`macOS`, `iOS`) |
| Root toggle variables | `include_<feature>` (boolean) | `include_categories`, `include_mac_cis_lvl1_benchmark`, `include_mobile_device_kickstart`, `include_jsc_all_services` | These usually control `count = ... ? 1 : 0` in the root `main.tf` |
| Provider/service input vars | `<service>_<field>` | `jamfpro_instance_url`, `jamfpro_client_id`, `jamfprotect_client_password`, `jsc_username`, `okta_client_id` | Keep secrets `sensitive = true` |
| Terraform resource labels | `<object>_<intent>` | `category_network` (Jamf Pro categories module), `app_installers` (App Installers module) | Use stable names so diffs stay readable |
| Support file naming | Put artifacts under `support_files/` and use versioned filenames where needed | `support_files/mobile_configuration_profiles/iOS26_cis_lvl1_enterprise-mail.managed.mobileconfig`, `support_files/defendermau.mobileconfig`, `support_files/onboarding.tpl` | Do not embed secrets in these files |

### Sensitivity

- Mark secrets as `sensitive = true` in variables/outputs where applicable.
- Never commit credentials, tokens, state, or local tfvars.

## Module structure

Each module under `modules/` should follow a predictable layout:

- `main.tf`: resources and primary logic.
- `locals.tf`: local values used to reduce repetition (when needed).
- `variables.tf`: inputs (documented).
- `outputs.tf`: outputs when useful.
- `README.md`: what it does, prerequisites, and any manual steps.
- `support_files/`: non-Terraform artifacts (e.g., `.mobileconfig`, scripts, templates).

Module tree example:

```text
modules/
|-- compliance-iOS-cis-level-1/
|   |-- README.md
|   |-- main.tf
|   |-- variables.tf
|   `-- support_files/
|       `-- mobile_configuration_profiles/
|           |-- iOS17_cis_lvl1_enterprise-applicationaccess.mobileconfig
|           |-- iOS18_cis_lvl1_enterprise-mail.managed.mobileconfig
|           `-- iOS26_cis_lvl1_enterprise-mobiledevice.passwordpolicy.mobileconfig
|-- endpoint-security-macOS-microsoft-defender/
|   |-- README.md
|   |-- locals.tf
|   |-- main.tf
|   |-- variables.tf
|   `-- support_files/
|       |-- defendermau.mobileconfig
|       `-- onboarding.tpl
`-- configuration-jamf-pro-categories/
    |-- README.md
    |-- main.tf
    `-- variables.tf
```

### Provider aliases

Modules should be written to support aliased providers.

- In the module: declare providers with `configuration_aliases`.
- In the root: pass aliases using `providers = { ... }` in the module block.

This allows running subsets of modules with only the credentials required for that module.

## Jamf-specific conventions

### Resources

- Prefer stable names and predictable scoping.
- When creating Jamf objects (profiles, policies, smart groups), avoid default "blast radius" where possible.
  - Many modules intentionally ship with smart groups that do not automatically target all devices.
  - If you need broader scope, document it clearly in the module README.

### Support files

- Store `.mobileconfig`, scripts, and templates under the module's `support_files/` directory.
- Do not embed secrets in profiles or scripts.
- Prefer versioned filenames when platform versions matter (e.g., include OS/version in the filename).

## Documentation conventions

### Module README

At minimum, module READMEs should answer:

- What will be created/changed in Jamf?
- Which provider credentials are required?
- Any required manual edits to payloads or templates.
- How to safely scope / test (e.g., serial-number criteria vs all devices).

### Root README

If you introduce a new top-level knob (especially an `include_...` toggle), update documentation or `spec.yml` so it's discoverable.

## `spec.yml` conventions

`spec.yml` is used by CI to apply options one-by-one.

When adding a new option:

- Keep the `key` aligned with the Terraform variable name.
- Provide:
  - `type: <boolean>`
  - `module_name` (e.g., `module.configuration-jamf-pro-categories`)
  - `required_provider` (e.g., `jpro`, `jsc`)
  - `category`, `display_name`, `display_desc`

## CI-friendly changes

- Keep applies idempotent.
- Avoid changes that depend on local-only files.
- Avoid long-running, high-parallelism patterns (Jamf APIs may require delays/low parallelism).
