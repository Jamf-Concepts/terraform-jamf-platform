# Workbrew Management for macOS

This module deploys all necessary Jamf Pro resources to manage and deploy Workbrew to macOS devices. It creates the scripts, packages, profiles, policies, and smart groups required for a complete Workbrew deployment.

## What This Module Creates

- **Category**: "Workbrew" for organizing all Workbrew-related resources
- **Scripts**: 
  - Workbrew activation script for device enrollment
  - Extension attribute scripts for Homebrew and Workbrew version tracking
- **Package**: Workbrew installer package retrieved from Workbrew CDN
- **Configuration Profile**: Managed login item profile for Workbrew agent
- **Extension Attributes**:
  - Workbrew Installed (detects if Workbrew is present)
  - Workbrew Version (reports installed Workbrew version)
  - Homebrew Version (reports installed Homebrew version)
- **Smart Computer Group**: Targets eligible macOS devices for Workbrew deployment
- **Policy**: Automated deployment policy to install and configure Workbrew

## Prerequisites

Before using this module, you must:

1. **Complete Stage 1**: Deploy the `configuration-jamf-pro-api-role-client-workbrew` module
2. **Register with Workbrew**: Upload your Jamf Pro API credentials to Workbrew Console
3. **Obtain Workspace API Key**: Get your Workspace API Key from Workbrew Console

## Usage

```hcl
module "workbrew_deployment" {
  source = "./modules/management-macOS-workbrew"

  workbrew_workspace_api_key = var.workbrew_workspace_api_key

  providers = {
    jamfpro = jamfpro
  }
}
```

### With Variable Configuration

```hcl
variable "workbrew_workspace_api_key" {
  description = "Workbrew Workspace API Key obtained from Workbrew Console"
  type        = string
  sensitive   = true
}

module "workbrew_deployment" {
  source = "./modules/management-macOS-workbrew"

  workbrew_workspace_api_key = var.workbrew_workspace_api_key

  providers = {
    jamfpro = jamfpro
  }
}
```

## Two-Stage Deployment Pattern

This is **Stage 2** of the Workbrew deployment workflow:

**Stage 1** (API Credentials):
```hcl
module "workbrew_credentials" {
  source = "./modules/configuration-jamf-pro-api-role-client-workbrew"
}
```

**Stage 2** (This Module - Resource Deployment):
```hcl
module "workbrew_deployment" {
  source = "./modules/management-macOS-workbrew"
  
  workbrew_workspace_api_key = var.workbrew_workspace_api_key
}
```

## Variables

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `workbrew_workspace_api_key` | Workspace API Key from Workbrew Console | `string` | Yes |
| `jamfpro_instance_url` | Jamf Pro instance URL (inherited from provider) | `string` | Yes |
| `jamfpro_client_id` | Jamf Pro OAuth Client ID (inherited from provider) | `string` | Yes |
| `jamfpro_client_secret` | Jamf Pro OAuth Client Secret (inherited from provider) | `string` | Yes |

## Related Modules

- [`configuration-jamf-pro-api-role-client-workbrew`](../configuration-jamf-pro-api-role-client-workbrew/README.md) - Creates API credentials for Workbrew (Stage 1)
