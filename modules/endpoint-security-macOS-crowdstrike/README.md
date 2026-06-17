# CrowdStrike Falcon - macOS Module

This module creates the necessary pieces in Jamf Pro to deploy and manage CrowdStrike Falcon sensor on macOS endpoints.

## Required Variables

### Jamf Pro Account Details

```hcl
jamfpro_auth_method   = "oauth2" ## oauth2 or basic
jamfpro_instance_url  = "https://yourinstance.jamfcloud.com"
jamfpro_client_id     = ""
jamfpro_client_secret = ""
```

### CrowdStrike Configuration

```hcl
falcon_api_client_id = "" # CrowdStrike API Client ID
falcon_api_secret    = "" # CrowdStrike API Client Secret
falcon_customer_id   = "" # CrowdStrike Customer ID (CCID)
```

## What This Module Creates

- **Category**: "Crowdstrike" for organizing resources
- **Smart Computer Group**: "Crowdstrike Target Group" for controlled, phased deployment
- **Scripts**:
  - Falcon Sensor API Install — Downloads and installs the Falcon sensor via the CrowdStrike API with SHA256 verification, retry logic, and regional endpoint detection
  - Post Install CrowdStrike Falcon Sensor — Licenses the installed sensor using your CCID
- **Configuration Profile**: CrowdStrike Falcon Settings (PPPC, System Extensions, Content Filter, Notifications, Login Items)
- **Policy**: "Crowdstrike Falcon API Install" — Triggered at check-in, runs both scripts to install and license the sensor

## Obtaining Your CrowdStrike Credentials

### API Client ID & Secret
1. Sign in to the [CrowdStrike Falcon Console](https://falcon.crowdstrike.com)
2. Go to **Support and resources** > **API Clients and Keys**
3. Create a new API client with **Sensor Download** read permissions
4. Note the **Client ID** and **Client Secret**

### Customer ID (CCID)
1. In the Falcon Console, go to **Host setup and management** > **Deploy** > **Sensor downloads**
2. Your **Customer ID checksum (CCID)** is displayed at the top of the page

## Smart Computer Group - Controlled Deployment

The smart group is configured with restrictive criteria for **controlled, phased deployment**:
- Operating System Version ≥ 13.0
- Serial Number like "111222333444555" (placeholder)

**Deployment Strategy:**

1. **Test Phase**: Replace the placeholder serial number with a test device's serial number
2. **Verification**: Confirm CrowdStrike Falcon deploys and functions correctly on the test device
3. **Expand Scope**: Once verified, remove the serial number criterion in Jamf Pro to broaden deployment
4. **Production**: The smart group will then target all devices meeting the OS version requirement

This approach allows you to safely test the deployment before rolling out organization-wide.

## Implementation Notes

### Scripts

The install script (`falconinstall.sh`) automatically detects the correct regional CrowdStrike API endpoint, downloads the latest N-1 sensor version, verifies SHA256 integrity, and installs it. The post-install script (`PostinstallCrowdStrikeFalconSensor.sh`) licenses the sensor with your CCID.

Both scripts log to `/var/log/managed/` for troubleshooting.

### Configuration Profile

The configuration profile grants CrowdStrike Falcon the following permissions:
- **PPPC**: Full Disk Access for the Falcon sensor
- **System Extensions**: Allows CrowdStrike network and endpoint security extensions
- **Content Filter**: Enables CrowdStrike network content filtering
- **Login Items**: Allows CrowdStrike background services
- **Notifications**: Enables Falcon notifications

The profile is scoped to **All Computers** by default. Modify the scoping in the module or in Jamf Pro as needed.

## References

- [CrowdStrike Falcon for macOS](https://www.crowdstrike.com/products/endpoint-security/)
- [Jamf Pro Configuration Profiles](https://learn.jamf.com/bundle/jamf-pro-documentation-current/page/Configuration_Profiles.html)

## Support

For issues related to:
- **Terraform Module**: Open an issue in this repository
- **CrowdStrike Falcon**: Contact CrowdStrike Support
- **Jamf Pro**: Contact Jamf Support
