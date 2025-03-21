#!/bin/bash

jamfpro_instance_url="$1"
jamfpro_client_id="$2"
jamfpro_client_secret="$3"

# Obtain the bearer token
response=$(curl --silent --location --request POST "${jamfpro_instance_url}/api/oauth/token" \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "client_id=${jamfpro_client_id}" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_secret=${jamfpro_client_secret}")
access_token=$(echo "$response" | awk -F'"' '/"access_token":/ {print $4}')

# Check if token was retrieved successfully
if [ -z "$access_token" ] || [ "$access_token" == "null" ]; then
  echo "Failed to obtain bearer token. Exiting."
  exit 1
fi

# Make the API request using the token
response=$(curl --silent --location --request PUT "${jamfpro_instance_url}/api/v3/sso" \
  --header "accept: application/json" \
  --header "content-type: application/json" \
  --header "Authorization: Bearer $access_token" \
  --data ' {
  "configurationType": "OIDC",
  "oidcSettings": {
    "userMapping": "EMAIL"
  },
  "samlSettings": {
    "tokenExpirationDisabled": false,
    "userAttributeEnabled": false,
    "userAttributeName": " ",
    "groupAttributeName": "http://schemas.xmlsoap.org/claims/Group",
    "groupRdnKey": " ",
    "otherProviderTypeName": " ",
    "sessionTimeout": 480
  },
  "ssoForEnrollmentEnabled": false,
  "ssoBypassAllowed": false,
  "ssoEnabled": true,
  "ssoForMacOsSelfServiceEnabled": false,
  "enrollmentSsoForAccountDrivenEnrollmentEnabled": false,
  "groupEnrollmentAccessEnabled": false,
  "groupEnrollmentAccessName": " "
}')
