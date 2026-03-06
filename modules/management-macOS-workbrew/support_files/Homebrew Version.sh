#!/bin/bash

BREW_BIN="/opt/workbrew/bin/brew"

if [[ -x "$BREW_BIN" ]]; then
	HOMEBREW_VERSION=$("$BREW_BIN" --version 2>/dev/null | awk '/^Homebrew / {print $2}')
	
	if [[ -n "$HOMEBREW_VERSION" ]]; then
		echo "<result>$HOMEBREW_VERSION</result>"
	else
		echo "<result>Installed (version unknown)</result>"
	fi
else
	echo "<result>Not Installed</result>"
fi
