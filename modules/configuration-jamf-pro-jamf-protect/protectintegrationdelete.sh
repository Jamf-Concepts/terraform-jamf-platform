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
access_token=$(echo "$response" | awk -F'"' '/"access_token":/ {print $4}')

response=$(curl --silent --location --request DELETE "${jamfpro_instance_url}/api/v1/jamf-protect" \
	 --header "Authorization: Bearer $access_token" \
     --header "accept: application/json" \
     --header "content-type: application/json")