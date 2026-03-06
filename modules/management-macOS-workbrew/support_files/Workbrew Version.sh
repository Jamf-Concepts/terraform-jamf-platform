#!/bin/bash

BREW_BIN="/opt/workbrew/bin/brew"

if [[ -x "$BREW_BIN" ]]; then
	WORKBREW_VERSION=$("$BREW_BIN" --version 2>/dev/null | awk '/^Workbrew / {print $2}')
	
	if [[ -n "$WORKBREW_VERSION" ]]; then
		echo "<result>$WORKBREW_VERSION</result>"
	else
		echo "<result>Installed (version unknown)</result>"
	fi
else
	echo "<result>Not Installed</result>"
fi