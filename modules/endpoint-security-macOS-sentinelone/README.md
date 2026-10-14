# SentinelOne Endpoint Protection - macOS Module

This module creates the necessary pieces in Jamf Pro to deploy and manage the SentinelOne agent on macOS devices in your environment.

## Required Variables

```hcl
sentinelone_org_token = ""  # Organization/site token from the SentinelOne console
```

You must also provide the package via **one** of the following methods:

```hcl
# Option 1: Local file path
sentinelone_pkg_path = "/path/to/.pkg"

# Option 2: S3 HTTPS URL (used by modular_onboarder CI/CD)
sentinelone_pkg_url = "https://bucket.s3.region.amazonaws.com/custom-files/session-id/file.pkg"
```

## Package Naming

Regardless of source, the module automatically extracts the application name and version from the `.pkg`'s embedded XAR metadata and names the package accordingly in Jamf Pro:

```
sentinel-agent-25.3.4.8365.pkg
```

This is derived from the `PackageInfo` or `Distribution` XML inside the package — the original uploaded filename is ignored entirely. The script that performs this extraction lives at [`tools/get_pkg_version.py`](../../tools/get_pkg_version.py) in the repository root and is shared across modules.

## What This Module Creates

- **Category**: `SentinelOne`
- **Configuration Profiles**:
  - SentinelOne - Service Management (Managed Login Items)
  - SentinelOne - Network Filter Validation (Content Filter)
  - SentinelOne - Network Monitoring Extension (System Extensions)
  - SentinelOne - Privacy Control (PPPC / Full Disk Access)
- **Smart Computer Groups**:
  - `SentinelOne Target Group` — devices eligible for deployment (macOS >= 13.0, scoped to a placeholder serial number)
  - `SentinelOne Installed` — devices with the SentinelOne agent present
  - `SentinelOne NOT Installed` — devices missing the agent but with the Privacy Control profile applied
- **Package**: SentinelOne macOS agent installer, version-stamped and uploaded to Jamf Pro
- **Script**: `SentinelOne License and Install` — writes the registration token then runs the installer
- **Policy**: `Deploy SentinelOne Agent` — caches the package, runs the install script, triggers inventory update (scoped to Target Group, once per computer)

## Package Source Options

### Option 1: Local file path

Provide the full path to the `.pkg` file. The module copies it to the working directory, extracts the version, and uploads it to Jamf Pro with a clean versioned name.

```hcl
sentinelone_pkg_path = "/path/to/SentinelOne.pkg"
```

### Option 2: S3 URL (modular_onboarder / CI/CD)

Provide an S3 HTTPS URL. The module downloads the file at apply time using `aws s3 cp` (requires `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in the runner environment), extracts the version, and uploads to Jamf Pro.

```hcl
sentinelone_pkg_url = "https://bucket.s3.region.amazonaws.com/custom-files/session-id/file.pkg"
```

## Obtaining Your Installer Package

1. Sign in to the [SentinelOne Management Console](https://usea1-partners.sentinelone.net)
2. Go to **Sentinels** > **Packages**
3. Download the macOS `.pkg` installer for your desired agent version

## Implementation Notes

### Configuration Profiles

All four configuration profiles are scoped to **All Computers**. These profiles grant the system-level permissions (Full Disk Access, System Extensions, Network Filter, Managed Login Items) that the SentinelOne agent requires to function.

### Target Group — Scoped Deployment

The deployment policy is scoped to the `SentinelOne Target Group` smart group. By default this group targets devices with:
- macOS 13.0 or later
- Serial number matching placeholder `111222333444555`

Replace the serial number criterion with your test device before expanding deployment to your fleet.

### Deployment Policy

The policy runs **once per computer** at check-in. It caches the SentinelOne `.pkg` to the Jamf Waiting Room, then runs the install script which writes the organization token and executes the installer. An inventory update runs after installation to immediately reflect the device's application inventory.

## References

- [SentinelOne macOS Agent Requirements](https://support.sentinelone.com)
- [Jamf Pro Configuration Profiles](https://learn.jamf.com/bundle/jamf-pro-documentation-current/page/Configuration_Profiles.html)

## Support

For issues related to:
- **Terraform Module**: Open an issue in this repository
- **SentinelOne**: Contact SentinelOne Support
- **Jamf Pro**: Contact Jamf Support
