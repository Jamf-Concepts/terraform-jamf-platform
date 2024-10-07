#!/bin/bash

jamfpro_instance_url="$1"
jamfpro_client_id="$2"
jamfpro_client_secret="$3"
jamfprotect_url="$4"
jamfprotect_clientID="$5"
jamfprotect_client_password="$6"

response=$(curl --silent --location --request POST "${jamfpro_instance_url}/api/oauth/token" \
	 	--header "Content-Type: application/x-www-form-urlencoded" \
		--data-urlencode "client_id=${jamfpro_client_id}" \
		--data-urlencode "grant_type=client_credentials" \
		--data-urlencode "client_secret=${jamfpro_client_secret}")
access_token=$(echo "$response" | plutil -extract access_token raw -)

echo $access_token

response=$(curl --silent --location --request POST "${jamfpro_instance_url}/api/v1/jamf-protect/register" \
	 --header "Authorization: Bearer $access_token" \
     --header "accept: application/json" \
     --header "content-type: application/json" \
     --data '{"protectUrl": "'$jamfprotect_url'","clientId": "'$jamfprotect_clientID'","password": "'$jamfprotect_client_password'"}')

echo $response