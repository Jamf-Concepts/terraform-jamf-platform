#!/bin/zsh

# Download latest specified Crowdstrike pkg and install
# richard@richard-purves.com - 05/03/2022

# Is Crowdstrike already installed
if [ ! -d "/Applications/Falcon.app" ];
then
	echo "Crowdstrike missing. Proceeding with install."

	# Client ID, Client Secret for the API token. Then make a base64 version.
	clientid="$4"
	secret="$5"
	b64creds=$( printf "$clientid:$secret" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )

	# Set a default URL
	baseurl="https://api.crowdstrike.com"

	# Work out major os version
	majver=$( /usr/bin/sw_vers -productVersion | /usr/bin/cut -d "." -f1 )

	# Now use this to work out the API base url
	# Highly modified from @Dj Padzensky 's work which I was linked to PR
	# on mac admin's slack
	baseurl=$( /usr/bin/curl -s -v -X POST -d "client_id=${clientid}&client_secret=${secret}" "${baseurl}/oauth2/token" 2>&1 | awk '($2 == "Location:") {print $3}' | cut -d/ -f1-3 )
	[ -z "$baseurl" ] && baseurl="https://api.crowdstrike.com"

	# API Base URL and the various endpoints we need
	oauthtoken="$baseurl/oauth2/token"
	oauthrevoke="$baseurl/oauth2/revoke"

	# Define which version we want to get.
	# 0 means latest. 1 is N-1, 2 is N-2 and so on.
	version="1"

	# Now define the API query we need
	sensorlist="$baseurl/sensors/combined/installers/v1?sort=version%7Cdesc&offset=${version}&limit=1&filter=platform%3A%22mac%22"
	sensordl="$baseurl/sensors/entities/download-installer/v1"

	# Request bearer access token using the API
	token=$( /usr/bin/curl -s -X POST "$oauthtoken" -H "accept: application/json" -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=${clientid}&client_secret=${secret}" )

	# Extract the bearer token from the json output above
	if [ "$majver" -le 11 ];
	then
		bearer=$( /usr/bin/osascript -l 'JavaScript' -e "JSON.parse(\`$token\`).access_token" )
	else
		bearer=$( /usr/bin/plutil -extract access_token raw -o - - <<< "$token" )
	fi

	# Work out the CrowdStrike installer, grab the SHA256 hash and use that to download that installer
	sensorv=$( /usr/bin/curl -s -X GET "$sensorlist" -H "accept: application/json" -H "authorization: Bearer ${bearer}" )
	if [ "$majver" -le 11 ];
	then
		sensorname=$( /usr/bin/osascript -l 'JavaScript' -e "JSON.parse(\`$sensorv\`).resources[0].name" )
		sensorsha=$( /usr/bin/osascript -l 'JavaScript' -e "JSON.parse(\`$sensorv\`).resources[0].sha256" )
	else
		sensorname=$( /usr/bin/plutil -extract resources.0.name raw -o - - <<< "$sensorv" )
		sensorsha=$( /usr/bin/plutil -extract resources.0.sha256 raw -o - - <<< "$sensorv" )
	fi

	# Download the client. Retry if required up to 10 times.
	for loop in {1..10};
	do
		echo "Download attempt: [$loop / 10]"
		test=$( /usr/bin/curl -s -o /private/tmp/${sensorname} -H "Authorization: Bearer ${bearer}" -w "%{http_code}" "${sensordl}?id=${sensorsha}" )
		[ "$test" = "200" ] && break
	done

	# Invalidate access to the bearer token
	/usr/bin/curl -X POST "$oauthrevoke" -H "accept: application/json" -H "authorization: Basic ${b64creds}" -H "Content-Type: application/x-www-form-urlencoded" -d "token=${bearer}"

	# Did the download actually work. Error if not.
	[ "$test" != "200" ] && { echo "Download failed. Exiting."; exit 1; }

	# Finally install and clean up
	/usr/sbin/installer -target / -pkg /private/tmp/${sensorname}
	/bin/rm /private/tmp/${sensorname}
else
	echo "Crowdstrike already present."
fi

# All done!
exit 0
