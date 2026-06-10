# SentinelOne Endpoint Protection - macOS Module

This module creates the necessary pieces in Jamf Pro to deploy and manage the SentinelOne agent on macOS devices in your environment.

## Required Variables

### SentinelOne Configuration

```hcl
sentinelone_org_token = ""  # Organization/site token from the SentinelOne console
```

You must also provide the package via **one** of the following methods:

```hcl
# Option 1: Local file path (filename auto-derived via basename)
sentinelone_pkg_path = "/path/to/Sentinel-Release-25-3-4-8365_macos_v25_3_4_8365.pkg"

# Option 2: Base64-encoded package content (for CI/CD pipelines)
sentinelone_pkg_base64 = "..." # Package displays as "SentinelOne.pkg" in Jamf Pro
```

### Optional Variables

```hcl
sentinelone_pkg_filename = "SentinelOne.pkg"  # Override the display name in Jamf Pro (only needed for base64 mode)
```

## What This Module Creates

- **Category**: "SentinelOne" for organizing resources
- **Configuration Profiles**:
  - SentinelOne - Service Management (Managed Login Items)
  - SentinelOne - Network Filter Validation (Content Filter)
  - SentinelOne - Network Monitoring Extension (System Extensions)
  - SentinelOne - Privacy Control (PPPC / Full Disk Access)
- **Smart Computer Groups**:
  - "SentinelOne Target Group" — devices eligible for deployment (OS >= 13.0, scoped by serial number)
  - "SentinelOne Installed" — devices that have the SentinelOne agent
  - "SentinelOne NOT Installed" — devices missing the agent but with the Privacy Control profile
- **Package**: SentinelOne macOS agent installer uploaded to Jamf Pro
- **Script**: "SentinelOne License and Install" — writes the registration token and runs the installer
- **Policy**: "Deploy SentinelOne Agent" — caches the package, runs the install script, and triggers inventory update (scoped to the Target Group, runs once per computer)

## Package Source Options

The module supports two methods of providing the SentinelOne installer package:

### Option 1: File Path (recommended for local/manual use)

Provide the full path to the `.pkg` file. The filename in Jamf Pro is automatically derived from the path using `basename()`.

```hcl
sentinelone_pkg_path = "./support_files/Sentinel-Release-25-3-4-8365_macos_v25_3_4_8365.pkg"
```

### Option 2: Base64 Content (for CI/CD pipelines)

Provide the package content as a base64-encoded string. The module decodes it and writes it to a local file before uploading. The package displays as "SentinelOne.pkg" in Jamf Pro (or override with `sentinelone_pkg_filename`).

```hcl
sentinelone_pkg_base64 = "..." # e.g. from a secrets manager or CI artifact
```

## Obtaining Your Installer Package

1. Sign in to the [SentinelOne Management Console](https://usea1-partners.sentinelone.net)
2. Go to **Sentinels** > **Packages**
3. Download the macOS `.pkg` installer for your desired agent version
4. Provide it via `sentinelone_pkg_path` or encode it with `base64 -i <file>` for `sentinelone_pkg_base64`

## Implementation Notes

### Configuration Profiles

All four configuration profiles are scoped to **All Computers**. These profiles grant system-level permissions (Full Disk Access, System Extensions, Network Filter, Managed Login Items) that the SentinelOne agent requires to function properly.

### Target Group — Scoped Deployment

The deployment policy is scoped to the "SentinelOne Target Group" smart group. By default this group targets devices with:
- macOS 13.0 or later
- A specific serial number (placeholder `111222333444555` — update the criteria to match your target devices)

Edit the `jamfpro_smart_computer_group.sentinelone_target` resource to adjust scoping criteria for your environment.

### Deployment Policy

The policy runs **once per computer** at check-in. It caches the SentinelOne `.pkg` to the Jamf Pro Waiting Room, then runs the install script which writes the organization token and executes the installer. An inventory update (recon) runs after installation to immediately update the device's application inventory.

## References

- [SentinelOne macOS Agent Requirements](https://support.sentinelone.com)
- [Deploying SentinelOne with Jamf Pro](https://support.sentinelone.com)
- [Jamf Pro Configuration Profiles](https://learn.jamf.com/bundle/jamf-pro-documentation-current/page/Configuration_Profiles.html)

## Support

For issues related to:
- **Terraform Module**: Open an issue in this repository
- **SentinelOne**: Contact SentinelOne Support
- **Jamf Pro**: Contact Jamf Support
