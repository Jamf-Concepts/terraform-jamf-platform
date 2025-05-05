# Jamf Platform - SaaS Tenancy Control

This vignette deploys a complete SaaS Tenancy Control module in Jamf Pro and Jamf Security Cloud.

Provider versions used in this release:

- hashicorp/aws v4.67.0
- danjamf/jsctfprovider v>= 0.0.15

## Prerequisites

More details see https://github.com/Jamf-Concepts/saastenancy


## Module Overview
This Module will create the following resources:
If no TLS certificate and key are provided, a self-signed certificate will be created.
AWS:
- Amazon Linux 2023 EC2 instance ARM64
  - Nginx will be installed and configured to listen on port 443
- Security Group allowing https from 0.0.0/0
- Elastic IP
Jamf Pro:
- Configuration Profile containing the required certificates to be trusted
Jamf Security Cloud:
- DNS record matching the elastic IP to the SaaS Tenancy Control application url
