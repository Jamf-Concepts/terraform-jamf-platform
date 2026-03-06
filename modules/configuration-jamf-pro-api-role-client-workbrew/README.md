# Jamf Pro API Role & Client for Workbrew

This module creates the necessary Jamf Pro API Role and API Integration (Client) specifically for Workbrew integration. It configures the appropriate permissions and generates client credentials that Workbrew uses to communicate with your Jamf Pro instance.

## What This Module Creates

- **API Role**: A dedicated role named "Workbrew" with required permissions for Workbrew operations
- **API Integration (Client)**: A client integration named "Workbrew" with OAuth2 credentials
- **Client Credentials**: Automatically generated Client ID and Client Secret for authentication

## Required Permissions

The API Role is configured with the following permissions required for Workbrew functionality:

- **Read Jamf Pro Version**: Access to instance version information
- **Computer Management**: Read and update computer records
- **Mobile Device Management**: Read and update mobile device records
- **Script Management**: Create, read, update scripts
- **Package Management**: Create, read, update packages
- **Policy Management**: Create, read, update policies
- **Configuration Profile Management**: Create, read, update profiles
- **Smart Group Management**: Create, read, update smart groups
- **Category Management**: Create, read, update categories

## Usage

```hcl
module "workbrew_api_role_client" {
  source = "./modules/configuration-jamf-pro-api-role-client-workbrew"

  providers = {
    jamfpro = jamfpro
  }
}
```

## Outputs

After applying this module, retrieve the generated credentials:

```hcl
output "workbrew_client_id" {
  value       = module.workbrew_api_role_client.workbrew_client_id
  description = "Client ID for Workbrew integration"
  sensitive   = true
}

output "workbrew_client_secret" {
  value       = module.workbrew_api_role_client.workbrew_client_secret
  description = "Client Secret for Workbrew integration"
  sensitive   = true
}

output "workbrew_api_role_id" {
  value       = module.workbrew_api_role_client.workbrew_api_role_id
  description = "ID of the Workbrew API Role"
}

output "workbrew_api_integration_id" {
  value       = module.workbrew_api_role_client.workbrew_api_integration_id
  description = "ID of the Workbrew API Integration"
}
```

## Next Steps

After deploying this module:

1. **Retrieve Credentials**: Use Terraform outputs to get the Client ID and Client Secret
2. **Register with Workbrew**: Upload these credentials to your Workbrew Console at https://console.workbrew.com
3. **Obtain Workspace API Key**: Workbrew will provide a Workspace API Key after registration
4. **Deploy Workbrew Resources**: Use the Workspace API Key with the `management-macOS-workbrew` module to deploy Workbrew to your devices

## Two-Stage Deployment Pattern

This module is designed for a two-stage deployment workflow:

**Stage 1** (This Module):
```hcl
module "workbrew_credentials" {
  source = "./modules/configuration-jamf-pro-api-role-client-workbrew"
}
```

**Stage 2** (After Workbrew Registration):
```hcl
module "workbrew_deployment" {
  source = "./modules/management-macOS-workbrew"
  
  workbrew_workspace_api_key = var.workbrew_workspace_api_key  # Obtained from Workbrew Console
}
```

## Security Considerations

- **Credentials are sensitive**: The Client Secret is only shown once during creation. Store it securely.
- **Least Privilege**: The API Role only includes permissions required for Workbrew operations.
- **Scope**: Credentials are scoped specifically to Workbrew integration and should not be used for other purposes.

## Related Modules

- [`management-macOS-workbrew`](../management-macOS-workbrew/README.md) - Deploys Workbrew resources to devices (Stage 2)