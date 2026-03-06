# Microsoft Entra Platform SSO Module

This module automates the deployment of Microsoft Entra Platform Single Sign-On (PSSO) for macOS devices managed by Jamf Pro.

## Overview

Platform SSO enables users to authenticate to their Mac using Microsoft Entra ID (formerly Azure AD) credentials, providing a seamless sign-in experience across macOS and Microsoft services.

## What This Module Creates

- **Category**: Microsoft Entra PSSO
- **Smart Groups**:
  - Target Group (macOS 14.0+, placeholder serial number included)
  - Exclusion Group (devices with Jamf Connect installed)
- **Package**: Microsoft Company Portal installer
- **Policy**: Automated installation of Company Portal
- **Configuration Profile**: PSSO settings and extension configuration

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Jamf Pro instance with API access
- Microsoft Entra ID tenant
- Devices must not be using Jamf Connect (automatically excluded)

## Required Variables

### Jamf Pro Authentication

```hcl
jamfpro_auth_method   = "oauth2"  # or "basic"
jamfpro_instance_url  = "https://your-instance.jamfcloud.com"
jamfpro_client_id     = "your-client-id"
jamfpro_client_secret = "your-client-secret"
jamfpro_username      = ""  # only for basic auth
jamfpro_password      = ""  # only for basic auth
```

**Note**: Use either OAuth2 credentials (client_id/secret) or basic authentication (username/password), not both.

## Usage

```hcl
module "microsoft_psso" {
  source = "./modules/management-microsoft-psso"
  
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_auth_method   = "oauth2"
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
}
```

## Deployment Process

1. **Initial Deployment**: The module creates all resources with a safety mechanism
2. **Test on Pilot Devices**: Add test device serial numbers to the Target Group
3. **Remove Placeholder**: Delete the placeholder serial number `111222333444555` from the Target Group
4. **Automatic Scope**: Profiles will deploy to all eligible devices