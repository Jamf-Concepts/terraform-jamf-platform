#!/bin/bash

# Check if token parameter is provided
if [[ -z "$4" ]]; then
    echo "Error: Token parameter (\$4) is required but not provided"
    exit 1
fi

# Set Workbrew home directory based on OS
if [[ $OSTYPE == darwin* ]]; then
    WORKBREW_HOME="/opt/workbrew/home/Library/Application Support/com.workbrew.workbrew-agent"
        else
    WORKBREW_HOME="/opt/workbrew/home/.local/share/workbrew"
fi

# Create Workbrew home directory with proper permissions
sudo mkdir -pv "${WORKBREW_HOME}"
sudo chmod 700 "${WORKBREW_HOME}"

# Write the token from parameter 4 to the API key file
echo "$4" | sudo tee "${WORKBREW_HOME}/api_key"

# Install Command Line Tools on macOS if not present
if [[ $OSTYPE == darwin* && ! -f "/Library/Developer/CommandLineTools/usr/bin/git" ]]; then
    CLT_PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    sudo touch "${CLT_PLACEHOLDER}"
  CLT_PACKAGE="$(softwareupdate -l | grep -B 1 "Command Line Tools" | awk -F"*" '/^ *\*/ {print $2}' | sed -e 's/^ *Label: //' -e 's/^ *//' | sort -V | tail -n1)"
    sudo softwareupdate -i --verbose "${CLT_PACKAGE}"
    sudo rm -vf "${CLT_PLACEHOLDER}"
fi