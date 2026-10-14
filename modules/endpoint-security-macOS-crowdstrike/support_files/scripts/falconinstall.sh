#!/bin/zsh

##########################################################################################
#
# Copyright (c) 2025, Jamf Software, LLC.  All rights reserved.
#
#       Redistribution and use in source and binary forms, with or without
#       modification, are permitted provided that the following conditions are met:
#               * Redistributions of source code must retain the above copyright
#                 notice, this list of conditions and the following disclaimer.
#               * Redistributions in binary form must reproduce the above copyright
#                 notice, this list of conditions and the following disclaimer in the
#                 documentation and/or other materials provided with the distribution.
#               * Neither the name of the JAMF Software, LLC nor the
#                 names of its contributors may be used to endorse or promote products
#                 derived from this software without specific prior written permission.
#
#       THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#       EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#       WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#       DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#       DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#       (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#       LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#       ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#       (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#       SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
##########################################################################################
#
# DESCRIPTION
# Downloads and installs the specified CrowdStrike Falcon sensor via the CrowdStrike API.
# Validates credentials, detects the regional API endpoint, downloads the installer with
# retry/backoff, verifies SHA256 integrity, and installs the package.
#
# PARAMETERS
# $4 - CrowdStrike API Client ID
# $5 - CrowdStrike API Client Secret
#
# CREDITS
# Original script by richard@richard-purves.com (2022)
#
##########################################################################################
#
# CHANGE LOG
# 1.0 - Created (richard@richard-purves.com - 05/03/2022)
# 2.0 - Refactored: added input validation, SHA256 verification, retry backoff,
#        installer exit code checking, cleanup trap, structured logging, regional
#        API redirect detection via curl write-out, dropped macOS <=11 support.
#  		(Kyle Hoare - 31/03/2025)
#
##########################################################################################

##########################################################################################
################################### Global Variables #####################################
##########################################################################################

# Extension of the script (.py, .sh etc)..
scriptExtension=${0##*.}

# Overall name of the family of software we are installing, with extension removed
swTitle=$(/usr/bin/basename "$0" ."${scriptExtension}")

# Log directory
debugDir="/var/log/managed"

# Log file
debugFile="${debugDir}/${swTitle}.log"

# Script Version
ver="2.0"

# Return code
returncode=0

# Jamf parameters
clientid="${4:-}"
secret="${5:-}"

# Default API base URL
baseurl="https://api.crowdstrike.com"

# Sensor version offset: 0 = latest, 1 = N-1, 2 = N-2, etc.
sensorversion="1"

# Download retry settings
max_retries=10
retry_delay=3

# Temp file path (set later once we know the sensor name)
tmpfile=""

# Bearer token and base64 credentials (set during acquire_token)
bearer=""
b64creds=""

# Sensor metadata (set during query_sensor)
sensorname=""
sensorsha=""

##########################################################################################
#################################### Start functions #####################################
##########################################################################################


setup()
{

    # Make sure we're root & creating logging dirs

    if [[ $(/usr/bin/id -u) -ne 0 ]]
    then
        echo "This script must be run as root" 1>&2
        exit 1
    fi

    if [[ ! -d "${debugDir}" ]]
    then
        /bin/mkdir -p "${debugDir}"
        /bin/chmod -R 777 "${debugDir}"
    fi

    if [[ ! -f "${debugFile}" ]]
    then
        /usr/bin/touch "${debugFile}"
    fi

    # Log all stdout and stderr output to the debug log file

    exec > >(/usr/bin/tee "${debugFile}") 2>&1

    # Cleanup trap — removes temp file on any exit
    trap cleanup EXIT

}


start()
{

    # Logging start

    echo
    echo "###################-START-##################"
    echo
    echo "Running ${swTitle} Version ${ver}"
    echo
    echo "Started: $(/bin/date)"
    echo

}


finish()
{

    # Logging finish

    echo
    echo "Finished: $(/bin/date)"
    echo
    echo "###################-END-###################"

}


cleanup()
{

    # Remove temp installer file if it exists

    if [[ -n "$tmpfile" && -f "$tmpfile" ]]
    then
        /bin/rm -f "$tmpfile"
        echo "Cleaned up temp file: $tmpfile"
    fi

}


log()
{

    # Timestamped log output

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"

}


preflight()
{

    # Check if CrowdStrike is already installed

    if [[ -d "/Applications/Falcon.app" ]]
    then
        log "CrowdStrike Falcon already present. Nothing to do."
        finish
        exit 0
    fi

    log "CrowdStrike Falcon not found. Proceeding with install."

    # Validate Jamf parameters

    if [[ -z "$clientid" || -z "$secret" ]]
    then
        log "Error: Missing CrowdStrike API Client ID (\$4) or Client Secret (\$5)."
        returncode=1
        finish
        exit "$returncode"
    fi

}


acquire_token()
{

    # Request an OAuth token. If the API redirects to a regional host,
    # detect that via curl write-out and retry against the correct base URL.

    local oauthtoken="$baseurl/oauth2/token"
    local token_response
    local redirect_url
    local detected_base

    log "Checking for regional API redirect..."

    # Probe for a redirect without following it.
    redirect_url=$( /usr/bin/curl -s -o /dev/null \
        --max-redirs 0 \
        -w "%{redirect_url}" \
        -X POST "$oauthtoken" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${clientid}" \
        --data-urlencode "client_secret=${secret}" )

    # Extract base URL from redirect if present
    if [[ -n "$redirect_url" ]]
    then
        # Extract scheme + host, strip any port suffix like :443
        detected_base=$( echo "$redirect_url" | cut -d/ -f1-3 | sed 's/:[0-9]*$//' )
        log "Redirect detected: $redirect_url"
        log "Extracted base: $detected_base"

        if [[ "$detected_base" =~ ^https://api(\.[a-z0-9-]+)?\.crowdstrike\.com$ ]]
        then
            baseurl="$detected_base"
            log "Using regional API base: $baseurl"
            oauthtoken="$baseurl/oauth2/token"
        else
            log "Warning: Redirect base does not match expected pattern: $detected_base — using default."
        fi
    else
        log "No redirect. Using default API base: $baseurl"
    fi

    # Request the actual bearer token
    log "Requesting OAuth token from $baseurl..."
    token_response=$( /usr/bin/curl -s -X POST "$oauthtoken" \
        -H "accept: application/json" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "client_id=${clientid}" \
        --data-urlencode "client_secret=${secret}" )

    log "Token response length: ${#token_response} bytes"

    bearer=$( /usr/bin/plutil -extract access_token raw -o - - <<< "$token_response" 2>/dev/null ) || true

    if [[ -z "$bearer" ]]
    then
        log "Error: Failed to extract bearer token. Check API credentials."
        log "API response: $token_response"
        returncode=1
        finish
        exit "$returncode"
    fi

    # Encode credentials for later token revocation
    b64creds=$( printf '%s:%s' "$clientid" "$secret" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )

    log "OAuth token acquired."

}


query_sensor()
{

    # Query the CrowdStrike API for the sensor installer metadata

    local sensorlist="$baseurl/sensors/combined/installers/v1?sort=version%7Cdesc&offset=${sensorversion}&limit=1&filter=platform%3A%22mac%22"
    local sensorv

    log "Querying sensor installer list (offset: $sensorversion)..."
    sensorv=$( /usr/bin/curl -s -X GET "$sensorlist" \
        -H "accept: application/json" \
        -H "authorization: Bearer ${bearer}" )

    sensorname=$( /usr/bin/plutil -extract resources.0.name raw -o - - <<< "$sensorv" 2>/dev/null ) || true
    sensorsha=$( /usr/bin/plutil -extract resources.0.sha256 raw -o - - <<< "$sensorv" 2>/dev/null ) || true

    if [[ -z "$sensorname" || -z "$sensorsha" ]]
    then
        log "Error: Failed to extract sensor name or SHA256 from API response."
        log "API response: $sensorv"
        returncode=1
        finish
        exit "$returncode"
    fi

    log "Sensor: $sensorname"
    log "SHA256: $sensorsha"

    # Set the temp file path for the cleanup trap
    tmpfile="/private/tmp/${sensorname}"

}


download_sensor()
{

    # Download the sensor installer with retry and backoff

    local sensordl="$baseurl/sensors/entities/download-installer/v1"
    local http_code

    for (( attempt=1; attempt<=max_retries; attempt++ ))
    do
        log "Download attempt: [$attempt / $max_retries]"
        http_code=$( /usr/bin/curl -s -o "$tmpfile" \
            -H "Authorization: Bearer ${bearer}" \
            -w "%{http_code}" \
            "${sensordl}?id=${sensorsha}" )

        if [[ "$http_code" == "200" ]]
        then
            log "Download completed (HTTP $http_code)."
            break
        fi

        log "HTTP $http_code — retrying in ${retry_delay} seconds..."
        sleep "$retry_delay"
    done

    if [[ "$http_code" != "200" ]]
    then
        log "Error: Download failed after $max_retries attempts (last HTTP code: $http_code)."
        returncode=1
        finish
        exit "$returncode"
    fi

}


revoke_token()
{

    # Revoke the bearer token (best effort)

    local oauthrevoke="$baseurl/oauth2/revoke"

    log "Revoking OAuth token..."
    /usr/bin/curl -s -o /dev/null -X POST "$oauthrevoke" \
        -H "accept: application/json" \
        -H "authorization: Basic ${b64creds}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "token=${bearer}" || true

}


verify_download()
{

    # Verify download integrity using the SHA256 hash from the API

    log "Verifying download integrity..."
    local dl_sha
    dl_sha=$( /usr/bin/shasum -a 256 "$tmpfile" | /usr/bin/awk '{print $1}' )

    if [[ "$dl_sha" != "$sensorsha" ]]
    then
        log "Error: SHA256 mismatch!"
        log "  Expected: $sensorsha"
        log "  Got:      $dl_sha"
        returncode=1
        finish
        exit "$returncode"
    fi

    log "SHA256 verified."

}


install_sensor()
{

    # Install the CrowdStrike Falcon sensor package

    log "Installing $sensorname..."
    if /usr/sbin/installer -target / -pkg "$tmpfile"
    then
        log "Installation successful."
    else
        log "Error: installer exited with code $?."
        returncode=1
    fi

}


main()
{

    # Primary workflow

    preflight
    acquire_token
    query_sensor
    download_sensor
    revoke_token
    verify_download
    install_sensor

}


##########################################################################################
#################################### End functions #######################################
##########################################################################################


setup
start
main
finish
exit "${returncode:-0}"