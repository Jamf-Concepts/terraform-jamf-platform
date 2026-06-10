#!/bin/zsh

# ─────────────────────────────────────────────────────────────────────────────
# SentinelOne License and Install
# This script installs SentinelOne and registers it with the org token.
#
# Parameter 4 ($4): SentinelOne organization token
# Parameter 5 ($5): SentinelOne installer package filename
#
# PDF Reference: Section 1, Steps 9–21
# ─────────────────────────────────────────────────────────────────────────────

S1_TOKEN="$4"
S1_PKG_NAME="$5"

# Validate required parameters
if [[ -z "$S1_TOKEN" ]]; then
    echo "ERROR: SentinelOne organization token not provided (Parameter 4)"
    exit 1
fi

if [[ -z "$S1_PKG_NAME" ]]; then
    echo "ERROR: SentinelOne package filename not provided (Parameter 5)"
    exit 1
fi

WAITING_ROOM="/Library/Application Support/JAMF/Waiting Room"

# Write the registration token
echo "$S1_TOKEN" > "${WAITING_ROOM}/com.sentinelone.registration-token"

# Install the SentinelOne package
/usr/sbin/installer -pkg "${WAITING_ROOM}/${S1_PKG_NAME}" -target /

INSTALL_EXIT=$?

if [[ $INSTALL_EXIT -ne 0 ]]; then
    echo "ERROR: SentinelOne installation failed with exit code $INSTALL_EXIT"
    exit $INSTALL_EXIT
fi

echo "SentinelOne installed and licensed successfully."
exit 0
