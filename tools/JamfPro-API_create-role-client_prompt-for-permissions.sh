#!/bin/bash
# Ward
###########################################################################################
## Create an API Client ID and Client Secret with scoped permissions using Jamf Pro API	 ##
###########################################################################################

# --- Prompt for execution mode ---
echo "Run mode:"
select mode in "Production" "Dry Run"; do
  case $mode in
    "Production")
      dryrun=false
      break
      ;;
    "Dry Run")
      dryrun=true
      echo "[INFO] Running in dry run mode. No changes will be made."
      break
      ;;
    *) echo "Invalid option. Try again." ;;
  esac
done

# --- Prompt for API credentials and URL ---
read -p "Enter username: " username
read -s -p "Enter password: " password
echo
read -p "Enter Jamf Pro URL (e.g., https://example.jamfcloud.com): " url

# --- Prompt for last name and generate unique name tag ---
read -p "Enter your last name (for naming tag): " lastname
timestamp=$(date +%Y%m%d)

generate_word_suffix() {
  consonants=(b c d f g h j k l m n p r s t v z)
  vowels=(a e i o u)
  word=""
  for i in {1..3}; do
    word+=${consonants[$RANDOM % ${#consonants[@]}]}
    word+=${vowels[$RANDOM % ${#vowels[@]}]}
  done
  echo "$word"
}

rand_word=$(generate_word_suffix)
name_tag="${lastname}-${timestamp}-${rand_word}"

# --- Prompt for role type ---
echo "Choose API Role type:"
select role_type in "Create" "Read" "Update" "Delete" "Super Admin"; do
  case $role_type in
    "Create"|"Read"|"Update"|"Delete"|"Super Admin") break ;;
    *) echo "Invalid option. Try again." ;;
  esac
done

# --- Config based on role type ---
api_role_displayName="API Role - $role_type Access - ${name_tag}"
api_client_displayName="API Client - $role_type Access - ${name_tag}"
lifetime="600"

# --- Get bearer token ---
authresponse=$(curl -s -u "$username:$password" "$url/api/v1/auth/token" -X POST)
bearerToken=$(echo "$authresponse" | plutil -extract token raw -)

# --- Get all available privileges ---
json=$(curl --silent --request GET \
  --url "$url/api/v1/api-role-privileges" \
  --header "authorization: Bearer $bearerToken" \
  --header 'accept: application/json')

# --- Filter privileges based on selected role type ---
case $role_type in
  "Super Admin")
    privileges=$(echo "$json" | jq '[.privileges[]]')
    ;;
  "Read")
    privileges=$(echo "$json" | jq '[.privileges[] | select(test("(?i)read|view"))]')
    ;;
  "Update")
    privileges=$(echo "$json" | jq '[.privileges[] | select(test("(?i)update|send"))]')
    ;;
  "Delete")
    privileges=$(echo "$json" | jq '[.privileges[] | select(test("(?i)delete"))]')
    ;;
  "Create")
    privileges=$(echo "$json" | jq '[.privileges[] | select(test("(?i)create"))]')
    ;;
esac

# --- Abort if no privileges matched ---
if [[ $(echo "$privileges" | jq 'length') -eq 0 ]]; then
  echo "[ERROR] No privileges matched for role type: $role_type"
  exit 1
fi

# --- Dry run summary ---
if $dryrun; then
  echo "[DRY RUN] Would create API role: $api_role_displayName"
  echo "[DRY RUN] With privileges:"
  echo "$privileges" | jq
  echo "[DRY RUN] Would create API client: $api_client_displayName"
  exit 0
fi

# --- Create API Role ---
response=$(curl --request POST \
  --url "$url/api/v1/api-roles" \
  --header "authorization: Bearer $bearerToken" \
  --header 'accept: application/json' \
  --header 'content-type: application/json' \
  --data "{
    \"displayName\": \"$api_role_displayName\",
    \"privileges\": $privileges
}")

# --- Extract role name ---
displayName=$(echo "$response" | jq -r '.displayName')

# --- Create API Client ---
response=$(curl --request POST \
  --url "$url/api/v1/api-integrations" \
  --header "authorization: Bearer $bearerToken" \
  --header 'accept: application/json' \
  --header 'content-type: application/json' \
  --data "{
    \"displayName\": \"$api_client_displayName\",
    \"enabled\": true,
    \"accessTokenLifetimeSeconds\": $lifetime,
    \"authorizationScopes\": [\"$displayName\"]
}")

# --- Extract integration ID ---
Id=$(echo "$response" | jq -r '.id')

# --- Create client credentials ---
credentials_response=$(curl --request POST \
  --url "$url/api/v1/api-integrations/$Id/client-credentials" \
  --header "authorization: Bearer $bearerToken" \
  --header 'accept: application/json')

# --- Verify created role and display its privileges ---
echo "[INFO] Verifying role creation and listing assigned privileges..."
verify_response=$(curl --silent --request GET \
  --url "$url/api/v1/api-roles" \
  --header "authorization: Bearer $bearerToken" \
  --header 'accept: application/json')

role_id=$(echo "$verify_response" | jq -r --arg name "$api_role_displayName" '.results[] | select(.displayName == $name) | .id')

if [[ -n "$role_id" ]]; then
  role_check=$(curl --silent --request GET \
    --url "$url/api/v1/api-roles/$role_id" \
    --header "authorization: Bearer $bearerToken" \
    --header 'accept: application/json')

  echo "[SUCCESS] Role '$api_role_displayName' created with the following privileges:"
  echo "$role_check" | jq '.privileges'
else
  echo "[ERROR] Could not verify role creation."
fi

# --- Output client credentials (with spacing) ---
clientId=$(echo "$credentials_response" | jq -r '.clientId')
clientSecret=$(echo "$credentials_response" | jq -r '.clientSecret')

echo
echo
echo "clientId: $clientId"
echo "clientSecret: $clientSecret"

# --- Copy both values to clipboard in one block ---
clipboard_output="clientId: $clientId
clientSecret: $clientSecret"
echo "$clipboard_output" | pbcopy
echo "[INFO] Credentials copied to clipboard."

exit