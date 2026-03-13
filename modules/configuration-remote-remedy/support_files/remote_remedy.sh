#!/bin/bash
set -euo pipefail

ACTION="${4:-install}"
ARG_DEBUG="$(echo "${5:-false}" | tr '[:upper:]' '[:lower:]')"

LABEL="com.jamf.remoteremedy"
INSTALL_DIR="/usr/local/jamfremedy"
SCRIPT_PATH="${INSTALL_DIR}/RemoteRemedy2.sh"
PLIST_PATH="/Library/LaunchDaemons/${LABEL}.plist"

# Installer script version (bump on every change to this file)
INSTALLER_VERSION="0.5.9"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [RemoteRemedy-Installer] $*"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log "ERROR: Must run as root."
    exit 1
  fi
}

safe_bootout_if_loaded() {
  /bin/launchctl bootout system "$PLIST_PATH" >/dev/null 2>&1 || true
}

write_main_script() {
  /bin/mkdir -p "$INSTALL_DIR"
  /usr/sbin/chown root:wheel "$INSTALL_DIR"
  /bin/chmod 755 "$INSTALL_DIR"

  /bin/cat > "$SCRIPT_PATH" <<'REMOTEREMEDY_SCRIPT'
#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="0.5.161"
DEBUG_MODE="${1:-false}"

#######################################
# Constants
#######################################
PLIST="/Library/Managed Preferences/com.jamfremoteremedy.session.plist"
PLIST_KEY="RemoteRemedySession"
LOG_FILE="/var/log/jamf_remote_remedy.log"

STATE_DIR="/var/db/jamfremedy"
SSH_KEY_FILE="${STATE_DIR}/client_key"
SSH_CTRL_SOCKET="${STATE_DIR}/ssh_control_socket"

REMOTE_USER="remoteremedy"
REMOTE_PASS=""

# Remote access provisioning sentinel (reduces repeated kickstart)
PROVISION_FLAG="${STATE_DIR}/remote_access_provisioned_v1"

# Directory Services node (explicit local node avoids eDSPermissionError seen with dscl ".")
DS_NODE="/Local/Default"

# ARD (Apple Remote Desktop / Remote Management)
# ARD (Apple Remote Desktop / Remote Management)
KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
ARD_WAS_OFF_MARKER="${STATE_DIR}/ard_was_off"
SSH_WAS_OFF_MARKER="${STATE_DIR}/ssh_was_off"
SSH_PLIST="/System/Library/LaunchDaemons/ssh.plist"
ARD_PLIST="/System/Library/LaunchDaemons/com.apple.screensharing.plist"

# Constants for Notification
MANAGEMENT_ACTION_APP="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"

# Timing
CHECK_INTERVAL=10                 # sleep when no plist / invalid payload
PLIST_POLL_INTERVAL=10            # check for plist content changes
RETRY_DELAY=10                    # fixed SSH retry
HOLD_DOWN_SECONDS=15              # plist changes w/ same host: do not restart SSH
PLIST_ABSENCE_GRACE_SECONDS=30    # if plist is gone this long, stop SSH tunnel + delete user

# No-plist logging (rate-limited)
NO_PLIST_LOG_INTERVAL=60
NEXT_NO_PLIST_LOG=0

# Heartbeat
HEARTBEAT_INTERVAL=3600
LAST_HEARTBEAT=0

# Event Logging
LOGGING_ENDPOINT="https://loggingingress.prod.remoteremedy.jamfconcepts.com/"
LOGGING_API_KEY="1cbccee57ba6"
MD_Serial=""
MD_UDID=""
MD_Jamf_UUID=""
MD_Jamf_Server=""
LAST_LOG_CHECK=0
LAST_ARD_LOG_TS=""


# SSH_PID is no longer used directly; we rely on the control socket.

########################################
# Logging
########################################
log_base() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [RemoteRemedy] $*" | tee -a "$LOG_FILE"
}

log_critical() {
  log_base "$@"
}

log_debug() {
  if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
    log_base "$@"
  fi
}

log() {
  log_debug "$@"
}

########################################
# Helpers
########################################
safe_mkdir() {
  mkdir -p "$1"
  chmod 700 "$1"
  chown root:wheel "$1"
}


collect_host_metadata() {
  # Gather static metadata once
  MD_Serial=$(system_profiler SPHardwareDataType 2>/dev/null | awk '/Serial/ {print $4}')
  MD_UDID=$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $4}')
  
  if [[ -f "/Library/Preferences/com.jamfsoftware.jamf.plist" ]]; then
    MD_Jamf_UUID=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist device_id 2>/dev/null || true)
    # Strip protocol (https://) and trailing slashes
    MD_Jamf_Server=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url 2>/dev/null | sed -E 's|^https?://||; s|/*$||' || true)
  fi
}

send_event() {
  local event_type="$1"
  local extra_json="${2:-}"
  local timestamp
  # Note: Client side timestamp is informational only; server assigns authoritative timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # If we don't have a hostname (session not active), use "unknown" or skip?
  # Requirement says "hostname... as main key". If no session, we use "system".
  local session_host="${SESSION_HOSTNAME:-system}"
  
  # Construct JSON payload
  # Use python or ruby to safely construct JSON if available, but for shell limitation custom construction:
  # Minimally escape strings
  local json_body
  json_body=$(cat <<EOF
{
  "hostname": "${session_host}",
  "event_type": "${event_type}",
  "serial_number": "${MD_Serial}",
  "udid": "${MD_UDID}",
  "jamf_uuid": "${MD_Jamf_UUID}",
  "jamf_server": "${MD_Jamf_Server}",
  "admin_name": "${SESSION_ADMIN_NAME:-}",
  "admin_email": "${SESSION_ADMIN_EMAIL:-}",
  "client_timestamp": "${timestamp}"
}
EOF
)

  # Merge extra fields if present
  if [[ -n "$extra_json" ]]; then
      # Remove closing brace from main body
      json_body="${json_body%?}" 
      # Remove opening brace from extra
      local extra_content="${extra_json#?}"
      json_body="${json_body}, ${extra_content}"
  fi
  
  # Send async to avoid blocking main loop
  # DEBUG: Log payload
  log "DEBUG: Sending event ${event_type}..."
  log "DEBUG: Payload: ${json_body}"

  # Send synchronously for debugging to capture output
  local response
  local http_code
  
  # Capture Response
  response=$(curl -s -w "\n%{http_code}" -X POST "$LOGGING_ENDPOINT" \
      -H "x-api-key: $LOGGING_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$json_body" 2>&1)
      
  http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | sed '$d')

  log "DEBUG: Response Code: ${http_code}"
  log "DEBUG: Response Body: ${body}"
}

check_activity_logs() {
    local now
    now=$(date +%s)
    
    # First run initialization
    if (( LAST_LOG_CHECK == 0 )); then
        LAST_LOG_CHECK=$(( now - 60 )) # Look back 60s on startup
    fi
    
    local start_date
    # Use exact last check time; we handle deduplication by tracking the log event timestamp
    start_date=$(date -r "$LAST_LOG_CHECK" "+%Y-%m-%d %H:%M:%S")
    log "DEBUG: Checking activity logs since ${start_date}..."
    
    # 1. SSH Sessions (sshd)
    # Using default style (syslog) for easier text parsing
    
    # SSH Login

    # SSH session started
    local login_logs
    login_logs=$(/usr/bin/log show --start "$start_date" \
    --predicate 'process == "sshd-session" AND message CONTAINS "activating connection"' \
    2>/dev/null || true)

    { echo "$login_logs" | grep -F "activating connection" || true; } | while read -r line; do
    send_event "SSH_SESSION_STARTED"
    done
    
    # SSH Logout
    local logout_logs
    logout_logs=$(/usr/bin/log show --start "$start_date" --predicate 'process == "sshd" AND message CONTAINS "Disconnected"' 2>/dev/null || true)
     echo "$logout_logs" | grep "Disconnected" || true | while read -r line; do
        local user
        user=$(echo "$line" | sed -nE 's/.*Disconnected.*user ([^ ]+).*/\1/p')
         if [[ -n "$user" ]]; then
             send_event "SSH_LOGOUT" "{\"target_user\": \"${user}\"}"
        fi
    done

    # 2. Screen Sharing (screensharingd)
    # Optimized: Look for "set agent port" (START) or "closing connection" (STOP)
    local ard_logs
    ard_logs=$(/usr/bin/log show --start "$start_date" --predicate 'process == "screensharingd" AND (message CONTAINS "set agent port" OR message CONTAINS "closing connection")' 2>/dev/null || true)
    
    # Process logs using process substitution to avoid subshell variable loss
    while read -r line; do
        # DEBUG: Log the line we are parsing
        # log "DEBUG: Parsing screensharing line: $line"

        # Deduplication: Check timestamp
        local log_ts
        log_ts=$(echo "$line" | awk '{print $1 " " $2}')
        if [[ "$log_ts" == "$LAST_ARD_LOG_TS" ]]; then
            log "DEBUG: Skipping duplicate Screenshare event at $log_ts"
            continue
        fi
        LAST_ARD_LOG_TS="$log_ts"

        # Check for START (set agent port)
        if echo "$line" | grep -q "set agent port" && echo "$line" | grep -q "viewer"; then
             local uid
             # Extract UID: "... set agent port 13315 for auth uid 502 ..."
             uid=$(echo "$line" | sed -nE 's/.*for auth uid ([0-9]+).*/\1/p')
             log "DEBUG: Extracted UID: '$uid'"
             
             if [[ -n "$uid" ]]; then
                  local user
                  user=$(id -nu "$uid" 2>/dev/null || echo "uid:${uid}")
                  send_event "SCREENSHARE_START" "{\"target_user\": \"${user}\"}"
             fi
        # Check for STOP (closing connection)
        elif echo "$line" | grep -q "closing connection"; then
             log "DEBUG: Detected screenshare stop event."
             send_event "SCREENSHARE_STOP"
        fi
    done < <(echo "$ard_logs" | grep -E "set agent port|closing connection" || true)
    
    LAST_LOG_CHECK=$now
}

ssh_running() {
  if [[ -S "$SSH_CTRL_SOCKET" ]]; then
     if ! out=$(/usr/bin/ssh -O check -S "$SSH_CTRL_SOCKET" ignored_host 2>&1); then
         log_debug "SSH check failed (socket exists): $out"
         return 1
     fi
     return 0
  fi
  # access check avoidance: strict missing check
  # log_debug "SSH socket check: Socket file not found at $SSH_CTRL_SOCKET" 
  return 1
}

sanitize_field() {
  echo -n "${1:-}" | tr -d '\r\n' | xargs
}

kill_tree_term() {
  local pid="$1"
  local kids
  kids=$(pgrep -P "$pid" 2>/dev/null || true)
  for k in $kids; do
    kill_tree_term "$k"
  done
  kill -TERM "$pid" >/dev/null 2>&1 || true
}

user_uid() {
  /usr/bin/id -u "$1" 2>/dev/null || true
}

kill_user_processes() {
  local u="$1" uid pids
  uid="$(user_uid "$u")"
  [[ -z "$uid" ]] && return 0

  if /usr/bin/who | /usr/bin/awk '{print $1}' | /usr/bin/grep -qx "$u"; then
    log "WARN: Support user appears logged in (user=${u}); attempting to terminate user processes."
  fi

  /usr/bin/pkill -TERM -U "$uid" >/dev/null 2>&1 || true
  sleep 1
  /usr/bin/pkill -KILL -U "$uid" >/dev/null 2>&1 || true

  pids="$(/bin/ps -axo pid,uid,comm | /usr/bin/awk -v u="$uid" '$2==u {print $1":"$3}' | head -20 || true)"
  if [[ -n "$pids" ]]; then
    log "WARN: Processes still running for support user after pkill (uid=${uid}): ${pids}"
  else
    log "Support user processes terminated (uid=${uid})."
  fi
}

########################################
# Remote access enablement
########################################
screensharing_member() {
  /usr/sbin/dseditgroup -o checkmember -m "$REMOTE_USER" com.apple.access_screensharing >/dev/null 2>&1
}

needs_remote_access_provision() {
  # Provision if we haven't marked success before, or if membership drifted.
  [[ ! -f "$PROVISION_FLAG" ]] && return 0
  screensharing_member || return 0
  return 1
}

########################################
# Service Lifecycle & Permissions
########################################

ensure_services_ready() {
  # 1. SSH (Remote Login)
  # Check if SSH is enabled. If not, mark state and enable it.
  # Use launchctl to bypass TCC restrictions on systemsetup.
  if ! /bin/launchctl list com.openssh.sshd >/dev/null 2>&1; then
    if [[ ! -f "$SSH_WAS_OFF_MARKER" ]]; then
       /usr/bin/touch "$SSH_WAS_OFF_MARKER"
       log "Snapshot: Remote Login (SSH) is OFF; marked for restoration on exit."
    fi
     
    # Permanently enable (-w)
    /bin/launchctl load -w "$SSH_PLIST" >/dev/null 2>&1 || true
    log_critical "Service Activation: Remote Login (SSH) enabled via launchctl."
  else
    log_debug "Service Check: Remote Login (SSH) is already running."
  fi

  # 2. ARD (Screen Sharing)
  # Check if Screen Sharing is enabled. If not, mark state and enable it.
  # if ! /bin/launchctl list com.apple.screensharing >/dev/null 2>&1; then
  #     if [[ ! -f "$ARD_WAS_OFF_MARKER" ]]; then
  #         /usr/bin/touch "$ARD_WAS_OFF_MARKER"
  #         log "Snapshot: Screen Sharing is OFF; marked for restoration on exit."
  #     fi
  #     
  #     # Force Activate
  #     log_critical "Service Activation: Enabling Screen Sharing/ARD via kickstart..."
  #     
  #     # Configure first (secure default: specified users only)
  #     # "$KICKSTART" -configure -allowAccessFor -specifiedUsers >/dev/null 2>&1 || true
  #     
  #     # Activate
  #     # "$KICKSTART" -activate -restart -agent -console >/dev/null 2>&1 || true
  #     
  #     # Ensure enabled state (belt and suspenders)
  #     # /bin/launchctl enable system/com.apple.screensharing >/dev/null 2>&1 || true
  #     # /bin/launchctl kickstart -k system/com.apple.screensharing >/dev/null 2>&1 || true
  # else
  #     log_debug "Service Check: Screen Sharing is already running."
  # fi
}

restore_service_state() {
  # Restore SSH if it was originally off
  if [[ -f "$SSH_WAS_OFF_MARKER" ]]; then
      log "Service Restoration: Disabling Remote Login (SSH) (was off)."
      /bin/launchctl unload -w "$SSH_PLIST" >/dev/null 2>&1 || true
      /bin/rm -f "$SSH_WAS_OFF_MARKER"
  fi

  # Restore ARD if it was originally off
  # if [[ -f "$ARD_WAS_OFF_MARKER" ]]; then
  #     log "Service Restoration: Deactivating Screen Sharing (was off)."
  #     "$KICKSTART" -deactivate -stop >/dev/null 2>&1 || true
  #     /bin/rm -f "$ARD_WAS_OFF_MARKER"
  # fi
}

provision_session_user() {
  # Ensure services are up (idempotent check)
  ensure_services_ready

  log "Provisioning permissions for user=${REMOTE_USER}..."

  # 1. Screen Sharing Group
  if /usr/sbin/dseditgroup -o edit -a "$REMOTE_USER" -t user com.apple.access_screensharing >/dev/null 2>&1; then
    log_debug "Group Membership: User added to com.apple.access_screensharing."
  else
    log "WARN: Failed to add user to com.apple.access_screensharing."
  fi

  # 2. SSH Group
  if /usr/sbin/dseditgroup -o edit -a "$REMOTE_USER" -t user com.apple.access_ssh >/dev/null 2>&1; then
    log_debug "Group Membership: User added to com.apple.access_ssh."
  else
    # This group might not exist on all macOS versions if SSH is off, but we enabled SSH, so it should exist.
    log_debug "WARN: Failed to add user to com.apple.access_ssh (check if group exists)."
  fi

  # 3. ARD Specific Privileges (Kickstart)
  # Configure this user specifically with full privileges
  # "$KICKSTART" -configure -users "$REMOTE_USER" -access -on -privs -all >/dev/null 2>&1 || {
  #   log "WARN: kickstart failed to configure user privileges for ${REMOTE_USER}."
  # }
  
  # 4. Refresh ARD Agent (Synchronous Hard Refresh)
  # Force a full reload of the service to clear cached ACLs.
  # "Disable and re-enable" as requested by the OS error message.
  # Note: This relies on "kickstart" which may be blocked by TCC if not whitelisted by MDM.
  # log "Triggering synchronous ARD service restart (Hard Refresh) to apply permissions..."
  # "$KICKSTART" -deactivate -stop >/dev/null 2>&1 || true
  # "$KICKSTART" -activate -restart -agent -console >/dev/null 2>&1 || true
  
  log "Provisioning complete for user=${REMOTE_USER}."
  return 0
}

deprovision_session_user() {
  log "Deprovisioning permissions for user=${REMOTE_USER}..."

  # 1. Remove from Screen Sharing Group
  # We check membership to avoid unnecessary logs/errors, though dseditgroup handles it gracefully usually.
  if screensharing_member; then
    if /usr/sbin/dseditgroup -o edit -d "$REMOTE_USER" -t user com.apple.access_screensharing >/dev/null 2>&1; then
      log_debug "Group Membership: User removed from com.apple.access_screensharing."
    else
      log "WARN: Failed to remove user from com.apple.access_screensharing."
    fi
  fi

  # 2. Remove from SSH Group
  /usr/sbin/dseditgroup -o edit -d "$REMOTE_USER" -t user com.apple.access_ssh >/dev/null 2>&1 || true
  
  # Note: We do NOT stop the services here. We only remove access.
  # Services are stopped in restore_service_state on script exit.
  
  return 0
}

########################################
# Notifications
########################################
get_console_user() {
  # Robustly get the current GUI user using scutil, ignoring loginwindow
  /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }'
}

send_notification() {
  local title="$1"
  local msg="$2"
  
  local user
  user=$(get_console_user)
  
  # Don't notify if at login window (root) or unknown
  if [[ "$user" == "root" || -z "$user" ]]; then
    log_debug "Console user is root/empty; skipping notification."
    return 0
  fi
  
  local uid
  uid=$(user_uid "$user")
  if [[ -z "$uid" ]]; then
    log_debug "Could not find UID for user ${user}; skipping notification."
    return 0
  fi

  log_debug "Sending notification to user=${user} (uid=${uid}): ${msg}"

  # Try Management Action.app
  if [[ -x "$MANAGEMENT_ACTION_APP" ]]; then
    if /bin/launchctl asuser "$uid" "$MANAGEMENT_ACTION_APP" -message "$msg" -title "$title" >/dev/null 2>&1; then
      log_debug "Notification sent via Management Action."
      return 0
    else
      log_debug "Management Action failed to send notification."
    fi
  else
    log_debug "Management Action app not found at ${MANAGEMENT_ACTION_APP}; skipping notification."
  fi

  return 1
}

########################################
# Local account lifecycle (standard user)
########################################
ensure_support_user() {
  if [[ -z "${REMOTE_PASS:-}" ]]; then
    log "ERROR: REMOTE_PASS is empty; refusing to create/update support user (user=${REMOTE_USER})."
    return 1
  fi

  local created=0

  if /usr/bin/id "$REMOTE_USER" &>/dev/null; then
    if /usr/bin/dscl "$DS_NODE" -passwd "/Users/$REMOTE_USER" "$REMOTE_PASS" >/dev/null 2>&1; then
      log "Local account exists; password updated successfully (user=${REMOTE_USER})."
    else
      log "ERROR: Local account exists but password update FAILED (user=${REMOTE_USER})."
      return 1
    fi
  else
    local uid
    uid=$(/usr/bin/dscl "$DS_NODE" -list /Users UniqueID | /usr/bin/awk '{print $2}' | /usr/bin/sort -n | /usr/bin/tail -1)
    uid=$((uid + 1))

    if /usr/bin/dscl "$DS_NODE" -create "/Users/$REMOTE_USER" >/dev/null 2>&1 && \
       /usr/bin/dscl "$DS_NODE" -create "/Users/$REMOTE_USER" UserShell /bin/bash >/dev/null 2>&1 && \
       /usr/bin/dscl "$DS_NODE" -create "/Users/$REMOTE_USER" RealName "Jamf Remote Remedy User" >/dev/null 2>&1 && \
       /usr/bin/dscl "$DS_NODE" -create "/Users/$REMOTE_USER" UniqueID "$uid" >/dev/null 2>&1 && \
       /usr/bin/dscl "$DS_NODE" -create "/Users/$REMOTE_USER" PrimaryGroupID 20 >/dev/null 2>&1 && \
       /usr/bin/dscl "$DS_NODE" -create "/Users/$REMOTE_USER" NFSHomeDirectory "/Users/$REMOTE_USER" >/dev/null 2>&1 && \
       /usr/bin/dscl "$DS_NODE" -passwd "/Users/$REMOTE_USER" "$REMOTE_PASS" >/dev/null 2>&1; then

      /usr/sbin/createhomedir -c -u "$REMOTE_USER" >/dev/null 2>&1 || true
      log "Local account created successfully (user=${REMOTE_USER}, uid=${uid}, admin=false)."
      created=1
    else
      log "ERROR: Local account creation FAILED (user=${REMOTE_USER})."
      return 1
    fi
  fi

  # Only (re)provision remote access when required.
  if (( created == 1 )) || needs_remote_access_provision; then
    if provision_session_user; then
      /usr/bin/touch "$PROVISION_FLAG"
      /bin/chmod 600 "$PROVISION_FLAG"
      /usr/sbin/chown root:wheel "$PROVISION_FLAG"
      log "Remote access provisioning marked complete (${PROVISION_FLAG})."
      
      if (( created == 1 )); then
          send_event "USER_CREATED" "{\"target_user\": \"${REMOTE_USER}\"}"
      fi
    else
      log "WARN: Remote access provisioning failed; will retry later."
      return 1
    fi
  fi

  return 0
}

delete_support_user() {
  if ! /usr/bin/id "$REMOTE_USER" >/dev/null 2>&1; then
    log "Support account not present; nothing to delete (user=${REMOTE_USER})."
    return 0
  fi

  log "Deleting local support account using sysadminctl (user=${REMOTE_USER})."

  kill_user_processes "$REMOTE_USER"

  if /usr/sbin/sysadminctl -deleteUser "$REMOTE_USER" -secure >/dev/null 2>&1; then
    /bin/rm -f "$PROVISION_FLAG" >/dev/null 2>&1 || true
    log "Support account deleted successfully (user=${REMOTE_USER})."
    send_event "USER_DELETED" "{\"target_user\": \"${REMOTE_USER}\"}"
    return 0
  fi

  log "ERROR: sysadminctl failed to delete support account (user=${REMOTE_USER})."
  return 1
}

########################################
# SSH lifecycle
########################################
stop_ssh_tunnel() {
  local reason="${1:-unknown}"
  
  if ssh_running || [[ -S "$SSH_CTRL_SOCKET" ]]; then
    log_critical "Cleanup: stopping SSH tunnel (socket=${SSH_CTRL_SOCKET}, reason=${reason})."
    /usr/bin/ssh -O exit -S "$SSH_CTRL_SOCKET" ignored_host >/dev/null 2>&1 || true
    send_event "CLIENT_TUNNEL_CLOSED" "{\"reason\": \"${reason}\"}"
    
    # Give it a moment to close socket
    sleep 1
  fi
  
  # Force cleanup of socket if it persists (stale)
  if [[ -S "$SSH_CTRL_SOCKET" ]]; then
      /bin/rm -f "$SSH_CTRL_SOCKET"
  fi
  
  # Requirement: clean up remote access permissions (remove user from groups)
  deprovision_session_user || true

  # Requirement: delete the account upon stop of SSH tunnel.
  delete_support_user || true
  
  # Send disconnection notification if user was notified of start
  if [[ "${SESSION_NOTIFIED:-false}" == "true" ]]; then
      send_notification "Remote Support" "The remote support session has ended." || true
      SESSION_NOTIFIED="false"
  fi
}

on_exit() {
  local ec=$?
  log "Script exiting (exit_code=${ec}); cleaning up SSH tunnel and services."
  stop_ssh_tunnel "script_exit"
  restore_service_state
  exit "$ec"
}

trap on_exit EXIT HUP INT QUIT TERM

########################################
# SSH Reverse Tunnel
########################################
start_ssh_tunnel() {
  local host="$1"

  log "Attempting SSH tunnel start (host=${host}) via ControlSocket..."

  # -f: Requests ssh to go to background just before command execution.
  #     This implies that if ssh returns 0, the connection is ESTABLISHED and AUTHENTICATED.
  # -N: Do not execute a remote command.
  # -M: Places the ssh client into "master" mode for connection sharing.
  # -S: Specifies the location of a control socket  # Aggressive cleanup: Kill any ssh process using this specific control socket pattern
  # This prevents "Address already in use" errors from zombie processes
  /usr/bin/pkill -f "ssh.*-S ${SSH_CTRL_SOCKET}" || true

  # Start SSH in background manually (since -f breaks socket creation on this system)
  # We redirect stdout/stderr to log or /dev/null to prevent noise, but strict errors are hard to catch without -f waiting.
  /usr/bin/ssh -N \
    -M -S "$SSH_CTRL_SOCKET" \
    -i "$SSH_KEY_FILE" \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -R 0.0.0.0:9000:localhost:22 \
    -R 0.0.0.0:9001:localhost:5900 \
    "macssh@$host" >>"$LOG_FILE" 2>&1 &
    
  local job_pid=$!
  
  # Wait for socket to appear (max 15s)
  local checks=0
  while [[ ! -S "$SSH_CTRL_SOCKET" ]]; do
      # Check if process died prematurely
      if ! kill -0 "$job_pid" 2>/dev/null; then
          log_critical "ERROR: SSH process died immediately (pid=${job_pid}). Check logs."
          return 1
      fi
      
      if (( checks >= 15 )); then
          log_critical "ERROR: Timeout waiting for SSH socket creation (pid=${job_pid}). Killing process."
          kill "$job_pid" 2>/dev/null || true
          return 1
      fi
      
      sleep 1
      (( checks++ ))
  done
    
  log_critical "SSH tunnel ESTABLISHED (socket=${SSH_CTRL_SOCKET}, host=${host}, pid=${job_pid}, admin_name='${SESSION_ADMIN_NAME}', admin_email='${SESSION_ADMIN_EMAIL}')."
  send_event "CLIENT_TUNNEL_ESTABLISHED" "{\"local_user\": \"${REMOTE_USER}\", \"tunnel_host\": \"${host}\", \"script_version\": \"${SCRIPT_VERSION}\"}"
  return 0
}

########################################
# Session parsing
########################################
get_raw_plist_value() {
  /usr/bin/defaults read "$PLIST" "$PLIST_KEY" 2>/dev/null || true
}

parse_session_from_raw() {
  local raw="$1" decoded
  decoded=$(echo "$raw" | base64 --decode 2>/dev/null || true)
  [[ -z "$decoded" ]] && return 1

  IFS=',' read -r \
    SESSION_VERSION \
    SESSION_HOSTNAME \
    SESSION_CLIENT_KEY_B64 \
    SESSION_LOCAL_PASS \
    SESSION_ADMIN_NAME \
    SESSION_ADMIN_EMAIL \
    SESSION_EXPIRY <<< "$decoded"

  SESSION_VERSION=$(sanitize_field "$SESSION_VERSION")
  SESSION_HOSTNAME=$(sanitize_field "$SESSION_HOSTNAME")
  SESSION_CLIENT_KEY_B64=$(sanitize_field "$SESSION_CLIENT_KEY_B64")
  SESSION_LOCAL_PASS=$(sanitize_field "$SESSION_LOCAL_PASS")
  SESSION_ADMIN_NAME=$(sanitize_field "$SESSION_ADMIN_NAME")
  SESSION_ADMIN_EMAIL=$(sanitize_field "$SESSION_ADMIN_EMAIL")
  SESSION_EXPIRY=$(sanitize_field "$SESSION_EXPIRY")

  [[ "$SESSION_VERSION" != "v1" ]] && return 1
  [[ -z "$SESSION_HOSTNAME" ]] && return 1

  # Validate hostname strict allowlist
  if [[ "$SESSION_HOSTNAME" != *.remoteremedy.jamfconcepts.com ]]; then
      log_critical "ERROR: Hostname '${SESSION_HOSTNAME}' is not allowed. Only *.remoteremedy.jamfconcepts.com is accepted."
      return 1
  fi
  [[ -z "$SESSION_CLIENT_KEY_B64" ]] && return 1
  [[ -z "$SESSION_LOCAL_PASS" ]] && return 1
  [[ -z "$SESSION_EXPIRY" ]] && return 1

  REMOTE_PASS="$SESSION_LOCAL_PASS"
  return 0
}

apply_session_locally() {
  echo "$SESSION_CLIENT_KEY_B64" | base64 --decode >"$SSH_KEY_FILE" || return 1
  chmod 600 "$SSH_KEY_FILE"
  chown root:wheel "$SSH_KEY_FILE"

  ensure_support_user
}

########################################
# Main Loop
########################################
safe_mkdir "$STATE_DIR"

LAST_RAW=""
LAST_HOST=""
ACTIVE_HOST=""
LAST_SESSION_SIGNATURE=""
NEXT_PLIST_CHECK=0
HOLD_DOWN_UNTIL=0
PLIST_MISSING_SINCE=0
SESSION_EXPIRY_WARNED="false"
SESSION_NOTIFIED="false"

log_critical "Remote Remedy Script v${SCRIPT_VERSION} started (debug=${DEBUG_MODE})."

# Ensure services are ready immediately upon script start
ensure_services_ready
collect_host_metadata

while true; do
  now=$(date +%s)
  
  # Heartbeat
  if (( now - LAST_HEARTBEAT >= HEARTBEAT_INTERVAL )); then
      # Check if we just woke up from sleep (using a small buffer, e.g. 60s extra)
      if (( LAST_HEARTBEAT > 0 )) && (( now - LAST_HEARTBEAT > HEARTBEAT_INTERVAL + 60 )); then
          log_critical "Heartbeat (resumed from sleep/power-off)."
      else
          log_critical "Heartbeat (running)."
      fi
      LAST_HEARTBEAT=$now
  fi

  if [[ ! -f "$PLIST" ]]; then
    if (( PLIST_MISSING_SINCE == 0 )); then
      PLIST_MISSING_SINCE=$now
    fi

    missing_for=$(( now - PLIST_MISSING_SINCE ))
    if (( missing_for >= PLIST_ABSENCE_GRACE_SECONDS )); then
      if [[ -n "${LAST_HOST:-}" || -n "${ACTIVE_HOST:-}" ]]; then
        log_critical "Session plist missing for ${missing_for}s (>= ${PLIST_ABSENCE_GRACE_SECONDS}s); ensuring cleanup (deleting user)."
        stop_ssh_tunnel "plist_removed_grace_expired"
        send_event "PLIST_REMOVED"
        LAST_RAW=""
        LAST_HOST=""
        ACTIVE_HOST=""
        LAST_SESSION_SIGNATURE=""
      fi
    fi

    if (( now >= NEXT_NO_PLIST_LOG )); then
      log "No session plist detected at ${PLIST}; waiting."
      NEXT_NO_PLIST_LOG=$(( now + NO_PLIST_LOG_INTERVAL ))
    fi

    sleep "$CHECK_INTERVAL"
    continue
  fi

  PLIST_MISSING_SINCE=0
  NEXT_NO_PLIST_LOG=0

  if (( now < NEXT_PLIST_CHECK )); then
    sleep 2
    continue
  fi
  NEXT_PLIST_CHECK=$(( now + PLIST_POLL_INTERVAL ))

  # Check Unified Logging for Activity
  check_activity_logs

  RAW="$(get_raw_plist_value)"
  if [[ -z "$RAW" ]]; then
    if [[ -n "${LAST_HOST:-}" || -n "${ACTIVE_HOST:-}" ]]; then
      log_critical "Session payload removed from plist; ensuring cleanup (deleting user)."
      stop_ssh_tunnel "session_payload_removed"
      LAST_RAW=""
      LAST_HOST=""
      ACTIVE_HOST=""
      LAST_SESSION_SIGNATURE=""
    fi
    sleep "$CHECK_INTERVAL"
    continue
  fi

  if [[ "$RAW" != "$LAST_RAW" ]]; then
    if ! parse_session_from_raw "$RAW"; then
      log_critical "ERROR: Invalid session payload; will retry."
      sleep "$CHECK_INTERVAL"
      continue
    fi

    log "Configuration parsed (version=${SESSION_VERSION}, host=${SESSION_HOSTNAME}, expiry=${SESSION_EXPIRY})."

    if [[ -z "$LAST_RAW" ]]; then
        send_event "PLIST_DETECTED"
    else
        send_event "PLIST_UPDATED"
    fi

    # Reset suppression if host changed
    if [[ "$SESSION_HOSTNAME" != "$LAST_HOST" ]]; then
      SESSION_EXPIRY_WARNED="false"
      SESSION_NOTIFIED="false"
    fi

    now=$(date +%s)
    if (( now >= SESSION_EXPIRY )); then
      if [[ "${SESSION_EXPIRY_WARNED:-false}" != "true" ]]; then
        log_critical "Session defined in plist expired. Monitoring for updates to it... Stopping SSH tunnel (and deleting user)."
        SESSION_EXPIRY_WARNED="true"
        stop_ssh_tunnel "session_expired"
      else
        log_debug "Session defined in plist expired; monitoring only (now=${now} >= expiry=${SESSION_EXPIRY})."
      fi
      
      ACTIVE_HOST=""
      LAST_RAW="$RAW"
      LAST_HOST="$SESSION_HOSTNAME"
      HOLD_DOWN_UNTIL=0
      continue
    fi
    
    # Valid session (not expired)
    SESSION_EXPIRY_WARNED="false"

    # Signature Check: Prevent redundant provisioning (password resets) if only metadata (e.g. Expiry) changed
    CURRENT_SESSION_SIGNATURE="${SESSION_HOSTNAME}:${SESSION_LOCAL_PASS}:${SESSION_CLIENT_KEY_B64}"
    
    if [[ "$CURRENT_SESSION_SIGNATURE" != "$LAST_SESSION_SIGNATURE" ]]; then
        log_debug "Session Signature Change Detected! Old='${LAST_SESSION_SIGNATURE}' New='${CURRENT_SESSION_SIGNATURE}'"
        if apply_session_locally; then
            log "SSH key written/User provisioned successfully (${SSH_KEY_FILE}, mode=600)."
            LAST_SESSION_SIGNATURE="$CURRENT_SESSION_SIGNATURE"
        else
            log "ERROR: Failed to write SSH key or provision user; will retry."
            sleep "$CHECK_INTERVAL"
            continue
        fi
    else
        log_debug "Session signature unchanged; skipping redundant user provisioning."
    fi


    if [[ -n "${ACTIVE_HOST:-}" && "$SESSION_HOSTNAME" != "$ACTIVE_HOST" ]]; then
      log "Hostname changed (active=${ACTIVE_HOST} new=${SESSION_HOSTNAME}); restarting SSH now."
      stop_ssh_tunnel "hostname_changed"
      ACTIVE_HOST=""
      HOLD_DOWN_UNTIL=0
      # NOTE: removed redundant ensure_support_user call here; apply_session_locally already ensured it
    elif [[ -n "${LAST_HOST:-}" && "$SESSION_HOSTNAME" == "$LAST_HOST" ]]; then
      if (( HOLD_DOWN_SECONDS > 0 )); then
        if (( now >= HOLD_DOWN_UNTIL )); then
          HOLD_DOWN_UNTIL=$(( now + HOLD_DOWN_SECONDS ))
          log "Plist changed but host unchanged (host=${SESSION_HOSTNAME}); hold-down until ${HOLD_DOWN_UNTIL}; no restart."
        fi
      fi
    fi

    LAST_RAW="$RAW"
    LAST_HOST="$SESSION_HOSTNAME"
  fi

  if ssh_running && [[ -z "${ACTIVE_HOST:-}" ]]; then
    ACTIVE_HOST="$LAST_HOST"
  fi

  if ssh_running; then
    sleep 2
    continue
  fi

  if [[ -n "${LAST_HOST:-}" ]]; then
    now=$(date +%s)
    if [[ -n "${SESSION_EXPIRY:-}" ]] && (( now >= SESSION_EXPIRY )); then
      if [[ "${SESSION_EXPIRY_WARNED:-false}" != "true" ]]; then
        log_critical "Session is expired during reconnect check; ensuring cleanup."
        SESSION_EXPIRY_WARNED="true"
        stop_ssh_tunnel "session_expired_during_retry"
      else
        log_debug "Session is expired during reconnect check (now=${now} >= expiry=${SESSION_EXPIRY})."
      fi
      
      ACTIVE_HOST=""
      sleep "$CHECK_INTERVAL"
      continue
    fi

    # Ensure the local account exists before starting SSH
    ensure_support_user || {
      log "ERROR: Support user not ready; not starting SSH tunnel."
      sleep "$RETRY_DELAY"
      continue
    }

    if start_ssh_tunnel "$LAST_HOST"; then
      ACTIVE_HOST="$LAST_HOST"
      
      # Send notification if not yet notified for this session
      if [[ "${SESSION_NOTIFIED:-false}" != "true" ]]; then
          msg="${SESSION_ADMIN_NAME:-Unknown} (${SESSION_ADMIN_EMAIL:-Unknown}) has prepared a remote support session with your Mac."
          if send_notification "Remote Support" "$msg"; then
              SESSION_NOTIFIED="true"
          fi
      fi
    else
      log "SSH connection attempt failed; retrying in ${RETRY_DELAY}s (host=${LAST_HOST})."
      sleep "$RETRY_DELAY"
    fi
  else
    sleep "$CHECK_INTERVAL"
  fi
done
REMOTEREMEDY_SCRIPT

  /usr/sbin/chown root:wheel "$SCRIPT_PATH"
  /bin/chmod 755 "$SCRIPT_PATH"
}

write_launchdaemon() {
  /bin/cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${SCRIPT_PATH}</string>
      <string>${ARG_DEBUG}</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/var/log/jamf_remote_remedy.launchd.out.log</string>

    <key>StandardErrorPath</key>
    <string>/var/log/jamf_remote_remedy.launchd.err.log</string>
  </dict>
</plist>
PLIST

  /usr/sbin/chown root:wheel "$PLIST_PATH"
  /bin/chmod 644 "$PLIST_PATH"
}

load_launchdaemon() {
  safe_bootout_if_loaded
  /bin/launchctl bootstrap system "$PLIST_PATH"
  /bin/launchctl enable "system/${LABEL}" >/dev/null 2>&1 || true
  /bin/launchctl kickstart -k "system/${LABEL}" >/dev/null 2>&1 || true
}

uninstall_all() {
  log "Uninstall requested."
  safe_bootout_if_loaded
  /bin/rm -f "$PLIST_PATH"
  /bin/rm -f "$SCRIPT_PATH"
  log "Uninstalled ${LABEL} and removed ${SCRIPT_PATH}."
}

main() {
  require_root

  log "RemoteRemedy installer v${INSTALLER_VERSION} invoked (action=${ACTION}, debug=${ARG_DEBUG})."

  if [[ "$ACTION" == "uninstall" ]]; then
    uninstall_all
    exit 0
  fi

  log "Installing RemoteRemedy daemon + script."
  write_main_script
  write_launchdaemon
  load_launchdaemon

  log "Installed. LaunchDaemon label=${LABEL}, script=${SCRIPT_PATH}, plist=${PLIST_PATH}."
  /bin/launchctl print "system/${LABEL}" >/dev/null 2>&1 && log "LaunchDaemon is loaded." || log "WARNING: LaunchDaemon may not be loaded."
}

main