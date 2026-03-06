#!/bin/bash

if [[ -f "/opt/workbrew/bin/brew" ]]; then
	echo "<result>Installed</result>"
else
	echo "<result>Not Installed</result>"
fi