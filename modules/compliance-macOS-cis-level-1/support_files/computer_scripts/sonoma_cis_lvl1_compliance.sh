#!/bin/zsh --no-rcs

##  This script will attempt to audit all of the settings based on the installed profile.

##  This script is provided as-is and should be fully tested on a system that is not in a production environment.

###################  Variables  ###################

pwpolicy_file=""

###################  DEBUG MODE - hold shift when running the script  ###################

shiftKeyDown=$(osascript -l JavaScript -e "ObjC.import('Cocoa'); ($.NSEvent.modifierFlags & $.NSEventModifierFlagShift) > 1")

if [[ $shiftKeyDown == "true" ]]; then
    echo "-----DEBUG-----"
    set -o xtrace -o verbose
fi

###################  COMMANDS START BELOW THIS LINE  ###################

## Must be run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

ssh_key_check=0
if /usr/sbin/sshd -T &> /dev/null || /usr/sbin/sshd -G &>/dev/null; then
    ssh_key_check=0
else
    /usr/bin/ssh-keygen -q -N "" -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key
    ssh_key_check=1
fi

# path to PlistBuddy
plb="/usr/libexec/PlistBuddy"

# get the currently logged in user
CURRENT_USER=$( /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }')
CURR_USER_UID=$(/usr/bin/id -u $CURRENT_USER)

# get system architecture
arch=$(/usr/bin/arch)

# configure colors for text
RED='\e[31m'
STD='\e[39m'
GREEN='\e[32m'
YELLOW='\e[33m'

audit_plist="/Library/Preferences/org.cis_lvl1.audit.plist"
audit_log="/Library/Logs/cis_lvl1_baseline.log"

# pause function
pause(){
vared -p "Press [Enter] key to continue..." -c fackEnterKey
}

# logging function
logmessage(){
    if [[ ! $quiet ]];then
        echo "$(date -u) $1" | /usr/bin/tee -a "$audit_log"
    elif [[ ${quiet[2][2]} == 1 ]];then
        if [[ $1 == *" failed"* ]] || [[ $1 == *"exemption"* ]] ;then
            echo "$(date -u) $1" | /usr/bin/tee -a "$audit_log"
        else
            echo "$(date -u) $1" | /usr/bin/tee -a "$audit_log" > /dev/null
        fi
    else
        echo "$(date -u) $1" | /usr/bin/tee -a "$audit_log" > /dev/null
    fi
}

ask() {
    # if fix flag is passed, assume YES for everything
    if [[ $fix ]] || [[ $cfc ]]; then
        return 0
    fi

    while true; do

        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi

        # Ask the question - use /dev/tty in case stdin is redirected from somewhere else
        printf "${YELLOW} $1 [$prompt] ${STD}"
        read REPLY

        # Default?
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi

        # Check if the reply is valid
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac

    done
}

# function to display menus
show_menus() {
    lastComplianceScan=$(defaults read /Library/Preferences/org.cis_lvl1.audit.plist lastComplianceCheck)

    if [[ $lastComplianceScan == "" ]];then
        lastComplianceScan="No scans have been run"
    fi

    /usr/bin/clear
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "        M A I N - M E N U"
    echo "  macOS Security Compliance Tool"
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo "Last compliance scan: $lastComplianceScan
"
    echo "1. View Last Compliance Report"
    echo "2. Run New Compliance Scan"
    echo "3. Run Commands to remediate non-compliant settings"
    echo "4. Exit"
}

# function to read options
read_options(){
    local choice
    vared -p "Enter choice [ 1 - 4 ] " -c choice
    case $choice in
        1) view_report ;;
        2) run_scan ;;
        3) run_fix ;;
        4) exit 0;;
        *) echo -e "${RED}Error: please choose an option 1-4...${STD}" && sleep 1
    esac
}

# function to reset and remove plist file.  Used to clear out any previous findings
reset_plist(){
    if [[ $reset_all ]];then
        echo "Clearing results from all MSCP baselines"
        find /Library/Preferences -name "org.*.audit.plist" -exec rm -f '{}' \;
        find /Library/Logs -name "*_baseline.log" -exec rm -f '{}' \;
    else
        echo "Clearing results from /Library/Preferences/org.cis_lvl1.audit.plist"
        rm -f /Library/Preferences/org.cis_lvl1.audit.plist
        rm -f /Library/Logs/cis_lvl1_baseline.log
    fi
}

# Generate the Compliant and Non-Compliant counts. Returns: Array (Compliant, Non-Compliant)
compliance_count(){
    compliant=0
    non_compliant=0
    exempt_count=0
    
    rule_names=($(/usr/libexec/PlistBuddy -c "Print" $audit_plist | awk '/= Dict/ {print $1}'))
    
    for rule in ${rule_names[@]}; do
        finding=$(/usr/libexec/PlistBuddy -c "Print $rule:finding" $audit_plist)
        if [[ $finding == "false" ]];then
            compliant=$((compliant+1))
        elif [[ $finding == "true" ]];then
            is_exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey("$rule"))["exempt"]
EOS
)
            if [[ $is_exempt == "1" ]]; then
                exempt_count=$((exempt_count+1))
                non_compliant=$((non_compliant+1))
            else    
                non_compliant=$((non_compliant+1))
            fi
        fi
    done

    # Enable output of just the compliant or non-compliant numbers.
    if [[ $1 = "compliant" ]]
    then
        echo $compliant
    elif [[ $1 = "non-compliant" ]]
    then
        echo $non_compliant
    else # no matching args output the array
        array=($compliant $non_compliant $exempt_count)
        echo ${array[@]}
    fi
}

generate_report(){
    count=($(compliance_count))
    compliant=${count[1]}
    non_compliant=${count[2]}
    exempt_rules=${count[3]}

    total=$((non_compliant + compliant))
    percentage=$(printf %.2f $(( (compliant + exempt_rules) * 100. / total )) )
    echo
    echo "Number of tests passed: ${GREEN}$compliant${STD}"
    echo "Number of test FAILED: ${RED}$non_compliant${STD}"
    echo "Number of exempt rules: ${YELLOW}$exempt_rules${STD}"
    echo "You are ${YELLOW}$percentage%${STD} percent compliant!"
    pause
}

view_report(){

    if [[ $lastComplianceScan == "No scans have been run" ]];then
        echo "no report to run, please run new scan"
        pause
    else
        generate_report
    fi
}

# Designed for use with MDM - single unformatted output of the Compliance Report
generate_stats(){
    count=($(compliance_count))
    compliant=${count[1]}
    non_compliant=${count[2]}

    total=$((non_compliant + compliant))
    percentage=$(printf %.2f $(( compliant * 100. / total )) )
    echo "PASSED: $compliant FAILED: $non_compliant, $percentage percent compliant!"
}

run_scan(){
# append to existing logfile
if [[ $(/usr/bin/tail -n 1 "$audit_log" 2>/dev/null) = *"Remediation complete" ]]; then
 	echo "$(date -u) Beginning cis_lvl1 baseline scan" >> "$audit_log"
else
 	echo "$(date -u) Beginning cis_lvl1 baseline scan" > "$audit_log"
fi

# run mcxrefresh
/usr/bin/mcxrefresh -u $CURR_USER_UID

# write timestamp of last compliance check
/usr/bin/defaults write "$audit_plist" lastComplianceCheck "$(date +"%Y-%m-%d %H:%M:%S%z")"
    
#####----- Rule: audit_acls_files_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -le $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{print $1}' | /usr/bin/grep -c ":"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_acls_files_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_acls_files_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_acls_files_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_acls_files_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_acls_files_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_acls_files_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_acls_files_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_acls_files_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_acls_files_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_acls_files_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_acls_files_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_acls_files_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_acls_files_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_acls_folders_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -lde /var/audit | /usr/bin/awk '{print $1}' | /usr/bin/grep -c ":"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_acls_folders_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_acls_folders_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_acls_folders_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_acls_folders_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_acls_folders_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_acls_folders_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_acls_folders_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_acls_folders_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_acls_folders_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_acls_folders_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_acls_folders_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_acls_folders_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_acls_folders_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_auditd_enabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12, AU-12(1), AU-12(3)
# * AU-14(1)
# * AU-3, AU-3(1)
# * AU-8
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(LAUNCHD_RUNNING=$(/bin/launchctl list | /usr/bin/grep -c com.apple.auditd)
AUDITD_RUNNING=$(/usr/sbin/audit -c | /usr/bin/grep -c "AUC_AUDITING")
if [[ $LAUNCHD_RUNNING == 1 ]] && [[ -e /etc/security/audit_control ]] && [[ $AUDITD_RUNNING == 1 ]]; then
  echo "pass"
else
  echo "fail"
fi
)
    # expected result {'string': 'pass'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_auditd_enabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_auditd_enabled'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_auditd_enabled" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "pass" ]]; then
        logmessage "audit_auditd_enabled passed (Result: $result_value, Expected: \"{'string': 'pass'}\")"
        /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_auditd_enabled" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_auditd_enabled passed (Result: $result_value, Expected: "{'string': 'pass'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_auditd_enabled failed (Result: $result_value, Expected: \"{'string': 'pass'}\")"
            /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_auditd_enabled" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_auditd_enabled failed (Result: $result_value, Expected: "{'string': 'pass'}")"
        else
            logmessage "audit_auditd_enabled failed (Result: $result_value, Expected: \"{'string': 'pass'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_auditd_enabled" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_auditd_enabled failed (Result: $result_value, Expected: "{'string': 'pass'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_auditd_enabled does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool NO
fi

#####----- Rule: audit_control_acls_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -le /etc/security/audit_control | /usr/bin/awk '{print $1}' | /usr/bin/grep -c ":"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_acls_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_acls_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_control_acls_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_control_acls_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_control_acls_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_control_acls_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_control_acls_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_acls_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_control_acls_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_control_acls_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_acls_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_control_acls_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_control_acls_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_control_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -dn /etc/security/audit_control | /usr/bin/awk '{print $4}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_group_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_control_group_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_control_group_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_control_group_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_control_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_control_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_group_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_control_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_control_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_group_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_control_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_control_group_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_control_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -l /etc/security/audit_control | /usr/bin/awk '!/-r--[r-]-----|current|total/{print $1}' | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_mode_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_control_mode_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_control_mode_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_control_mode_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_control_mode_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_control_mode_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_mode_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_control_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_control_mode_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_mode_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_control_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_control_mode_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_control_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -dn /etc/security/audit_control | /usr/bin/awk '{print $3}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_owner_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_control_owner_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_control_owner_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_control_owner_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_control_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_control_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_owner_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_control_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_control_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_owner_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_control_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_control_owner_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_files_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -n $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{s+=$4} END {print s}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_group_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_files_group_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_files_group_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_files_group_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_files_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_files_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_group_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_files_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_files_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_group_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_files_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_files_group_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_files_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -l $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '!/-r--r-----|current|total/{print $1}' | /usr/bin/wc -l | /usr/bin/tr -d ' '
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_mode_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_files_mode_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_files_mode_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_files_mode_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_files_mode_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_files_mode_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_mode_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_files_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_files_mode_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_mode_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_files_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_files_mode_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_files_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -n $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{s+=$3} END {print s}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_owner_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_files_owner_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_files_owner_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_files_owner_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_files_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_files_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_owner_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_files_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_files_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_owner_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_files_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_files_owner_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_folder_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -dn $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{print $4}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folder_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folder_group_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_folder_group_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_folder_group_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_folder_group_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_folder_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_folder_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folder_group_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_folder_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_folder_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folder_group_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_folder_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_folder_group_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_folder_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -dn $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}') | /usr/bin/awk '{print $3}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folder_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folder_owner_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_folder_owner_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "audit_folder_owner_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_folder_owner_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_folder_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_folder_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folder_owner_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_folder_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_folder_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folder_owner_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_folder_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_folder_owner_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_folders_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/stat -f %A $(/usr/bin/grep '^dir' /etc/security/audit_control | /usr/bin/awk -F: '{print $2}')
)
    # expected result {'integer': 700}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folders_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folders_mode_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_folders_mode_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "700" ]]; then
        logmessage "audit_folders_mode_configure passed (Result: $result_value, Expected: \"{'integer': 700}\")"
        /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_folders_mode_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_folders_mode_configure passed (Result: $result_value, Expected: "{'integer': 700}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_folders_mode_configure failed (Result: $result_value, Expected: \"{'integer': 700}\")"
            /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folders_mode_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_folders_mode_configure failed (Result: $result_value, Expected: "{'integer': 700}")"
        else
            logmessage "audit_folders_mode_configure failed (Result: $result_value, Expected: \"{'integer': 700}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folders_mode_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_folders_mode_configure failed (Result: $result_value, Expected: "{'integer': 700}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_folders_mode_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_retention_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-11
# * AU-4
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F: '/expire-after/{print $2}' /etc/security/audit_control
)
    # expected result {'string': '60d OR 5G'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_retention_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_retention_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_retention_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "60d OR 5G" ]]; then
        logmessage "audit_retention_configure passed (Result: $result_value, Expected: \"{'string': '60d OR 5G'}\")"
        /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_retention_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - audit_retention_configure passed (Result: $result_value, Expected: "{'string': '60d OR 5G'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_retention_configure failed (Result: $result_value, Expected: \"{'string': '60d OR 5G'}\")"
            /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_retention_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_retention_configure failed (Result: $result_value, Expected: "{'string': '60d OR 5G'}")"
        else
            logmessage "audit_retention_configure failed (Result: $result_value, Expected: \"{'string': '60d OR 5G'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_retention_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - audit_retention_configure failed (Result: $result_value, Expected: "{'string': '60d OR 5G'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_retention_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool NO
fi

#####----- Rule: os_airdrop_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * AC-3
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowAirDrop').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_airdrop_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_airdrop_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_airdrop_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_airdrop_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_airdrop_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_airdrop_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_airdrop_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_airdrop_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_airdrop_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_airdrop_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_airdrop_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool NO
fi

#####----- Rule: os_anti_virus_installed -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl list | /usr/bin/grep -cE "(com.apple.XprotectFramework.PluginService$|com.apple.XProtect.daemon.scan$)"
)
    # expected result {'integer': 2}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_anti_virus_installed'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_anti_virus_installed'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_anti_virus_installed" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "2" ]]; then
        logmessage "os_anti_virus_installed passed (Result: $result_value, Expected: \"{'integer': 2}\")"
        /usr/bin/defaults write "$audit_plist" os_anti_virus_installed -dict-add finding -bool NO
        if [[ ! "$customref" == "os_anti_virus_installed" ]]; then
            /usr/bin/defaults write "$audit_plist" os_anti_virus_installed -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_anti_virus_installed passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_anti_virus_installed failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" os_anti_virus_installed -dict-add finding -bool YES
            if [[ ! "$customref" == "os_anti_virus_installed" ]]; then
                /usr/bin/defaults write "$audit_plist" os_anti_virus_installed -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_anti_virus_installed failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "os_anti_virus_installed failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_anti_virus_installed -dict-add finding -bool YES
            if [[ ! "$customref" == "os_anti_virus_installed" ]]; then
              /usr/bin/defaults write "$audit_plist" os_anti_virus_installed -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_anti_virus_installed failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_anti_virus_installed does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_anti_virus_installed -dict-add finding -bool NO
fi

#####----- Rule: os_authenticated_root_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-3
# * CM-5
# * MA-4(1)
# * SC-34
# * SI-7, SI-7(6)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/csrutil authenticated-root | /usr/bin/grep -c 'enabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_authenticated_root_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_authenticated_root_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_authenticated_root_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_authenticated_root_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_authenticated_root_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_authenticated_root_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_authenticated_root_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_authenticated_root_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_authenticated_root_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_authenticated_root_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_authenticated_root_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool NO
fi

#####----- Rule: os_config_data_install_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-2(5)
# * SI-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('ConfigDataInstall').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_config_data_install_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_config_data_install_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_config_data_install_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_config_data_install_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "os_config_data_install_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_config_data_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_config_data_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_config_data_install_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_config_data_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_config_data_install_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_config_data_install_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool NO
fi

#####----- Rule: os_firewall_log_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12
# * SC-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let pref1 = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.firewall')\
  .objectForKey('EnableLogging').js
  let pref2 = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.firewall')\
  .objectForKey('LoggingOption').js
  if ( pref1 == true && pref2 == "detail" ){
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_firewall_log_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_firewall_log_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_firewall_log_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_firewall_log_enable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_firewall_log_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_firewall_log_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_firewall_log_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_firewall_log_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_firewall_log_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_firewall_log_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_firewall_log_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_firewall_log_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_firewall_log_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool NO
fi

#####----- Rule: os_gatekeeper_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-14
# * CM-5
# * SI-3
# * SI-7(1), SI-7(15)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/spctl --status | /usr/bin/grep -c "assessments enabled"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_gatekeeper_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_gatekeeper_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_gatekeeper_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_gatekeeper_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_gatekeeper_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_gatekeeper_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_gatekeeper_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_gatekeeper_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_gatekeeper_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_gatekeeper_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_gatekeeper_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool NO
fi

#####----- Rule: os_guest_folder_removed -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls /Users/ | /usr/bin/grep -c "Guest"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_guest_folder_removed'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_guest_folder_removed'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_guest_folder_removed" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_guest_folder_removed passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add finding -bool NO
        if [[ ! "$customref" == "os_guest_folder_removed" ]]; then
            /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_guest_folder_removed passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_guest_folder_removed failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add finding -bool YES
            if [[ ! "$customref" == "os_guest_folder_removed" ]]; then
                /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_guest_folder_removed failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_guest_folder_removed failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add finding -bool YES
            if [[ ! "$customref" == "os_guest_folder_removed" ]]; then
              /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_guest_folder_removed failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_guest_folder_removed does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_guest_folder_removed -dict-add finding -bool NO
fi

#####----- Rule: os_home_folders_secure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/find /System/Volumes/Data/Users -mindepth 1 -maxdepth 1 -type d ! \( -perm 700 -o -perm 711 \) | /usr/bin/grep -v "Shared" | /usr/bin/grep -v "Guest" | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_home_folders_secure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_home_folders_secure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_home_folders_secure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_home_folders_secure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_home_folders_secure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_home_folders_secure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_home_folders_secure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_home_folders_secure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_home_folders_secure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_home_folders_secure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_home_folders_secure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool NO
fi

#####----- Rule: os_httpd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"org.apache.httpd" => disabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_httpd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_httpd_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_httpd_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_httpd_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_httpd_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_httpd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_httpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_httpd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_httpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_httpd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_httpd_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool NO
fi

#####----- Rule: os_install_log_retention_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-11
# * AU-4
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/aslmanager -dd 2>&1 | /usr/bin/awk '/\/var\/log\/install.log$/ {count++} /Processing module com.apple.install/,/Finished/ { for (i=1;i<=NR;i++) { if ($i == "TTL" && $(i+2) >= 365) { ttl="True" }; if ($i == "MAX") {max="True"}}} END{if (count > 1) { print "Multiple config files for /var/log/install, manually remove the extra files"} else if (max == "True") { print "all_max setting is configured, must be removed" } if (ttl != "True") { print "TTL not configured" } else { print "Yes" }}'
)
    # expected result {'string': 'Yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_install_log_retention_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_install_log_retention_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_install_log_retention_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "Yes" ]]; then
        logmessage "os_install_log_retention_configure passed (Result: $result_value, Expected: \"{'string': 'Yes'}\")"
        /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_install_log_retention_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_install_log_retention_configure passed (Result: $result_value, Expected: "{'string': 'Yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_install_log_retention_configure failed (Result: $result_value, Expected: \"{'string': 'Yes'}\")"
            /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_install_log_retention_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_install_log_retention_configure failed (Result: $result_value, Expected: "{'string': 'Yes'}")"
        else
            logmessage "os_install_log_retention_configure failed (Result: $result_value, Expected: \"{'string': 'Yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_install_log_retention_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_install_log_retention_configure failed (Result: $result_value, Expected: "{'string': 'Yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_install_log_retention_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool NO
fi

#####----- Rule: os_mdm_require -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-2
# * CM-6
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles status -type enrollment | /usr/bin/awk -F: '/MDM enrollment/ {print $2}' | /usr/bin/grep -c "Yes (User Approved)"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_mdm_require'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_mdm_require'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_mdm_require" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_mdm_require passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add finding -bool NO
        if [[ ! "$customref" == "os_mdm_require" ]]; then
            /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_mdm_require passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_mdm_require failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add finding -bool YES
            if [[ ! "$customref" == "os_mdm_require" ]]; then
                /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_mdm_require failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_mdm_require failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add finding -bool YES
            if [[ ! "$customref" == "os_mdm_require" ]]; then
              /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_mdm_require failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_mdm_require does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add finding -bool NO
fi

#####----- Rule: os_mobile_file_integrity_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/nvram -p | /usr/bin/grep -c "amfi_get_out_of_my_way=1"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_mobile_file_integrity_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_mobile_file_integrity_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_mobile_file_integrity_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_mobile_file_integrity_enable passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_mobile_file_integrity_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_mobile_file_integrity_enable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_mobile_file_integrity_enable failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_mobile_file_integrity_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_mobile_file_integrity_enable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_mobile_file_integrity_enable failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_mobile_file_integrity_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_mobile_file_integrity_enable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_mobile_file_integrity_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_mobile_file_integrity_enable -dict-add finding -bool NO
fi

#####----- Rule: os_nfsd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.nfsd" => disabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_nfsd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_nfsd_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_nfsd_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_nfsd_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_nfsd_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_nfsd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_nfsd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_nfsd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_nfsd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_nfsd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_nfsd_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool NO
fi

#####----- Rule: os_on_device_dictation_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch="arm64"
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('forceOnDeviceOnlyDictation').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_on_device_dictation_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_on_device_dictation_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_on_device_dictation_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_on_device_dictation_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "os_on_device_dictation_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_on_device_dictation_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_on_device_dictation_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_on_device_dictation_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_on_device_dictation_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_on_device_dictation_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_on_device_dictation_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_on_device_dictation_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_on_device_dictation_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool NO
fi

#####----- Rule: os_password_hint_remove -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-6
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(HINT=$(/usr/bin/dscl . -list /Users hint | /usr/bin/awk '{ print $2 }')

if [ -z "$HINT" ]; then
  echo "PASS"
else
  echo "FAIL"
fi
)
    # expected result {'string': 'PASS'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_password_hint_remove'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_password_hint_remove'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_password_hint_remove" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "PASS" ]]; then
        logmessage "os_password_hint_remove passed (Result: $result_value, Expected: \"{'string': 'PASS'}\")"
        /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool NO
        if [[ ! "$customref" == "os_password_hint_remove" ]]; then
            /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_password_hint_remove passed (Result: $result_value, Expected: "{'string': 'PASS'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_password_hint_remove failed (Result: $result_value, Expected: \"{'string': 'PASS'}\")"
            /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool YES
            if [[ ! "$customref" == "os_password_hint_remove" ]]; then
                /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_password_hint_remove failed (Result: $result_value, Expected: "{'string': 'PASS'}")"
        else
            logmessage "os_password_hint_remove failed (Result: $result_value, Expected: \"{'string': 'PASS'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool YES
            if [[ ! "$customref" == "os_password_hint_remove" ]]; then
              /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_password_hint_remove failed (Result: $result_value, Expected: "{'string': 'PASS'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_password_hint_remove does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool NO
fi

#####----- Rule: os_power_nap_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch="i386"
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pmset -g custom | /usr/bin/awk '/powernap/ { sum+=$2 } END {print sum}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_power_nap_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_power_nap_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_power_nap_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_power_nap_disable passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_power_nap_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_power_nap_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_power_nap_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_power_nap_disable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_power_nap_disable failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_power_nap_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_power_nap_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_power_nap_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_power_nap_disable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_power_nap_disable failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_power_nap_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_power_nap_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_power_nap_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_power_nap_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_power_nap_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_power_nap_disable -dict-add finding -bool NO
fi

#####----- Rule: os_root_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/dscl . -read /Users/root UserShell 2>&1 | /usr/bin/grep -c "/usr/bin/false"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_root_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_root_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_root_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_root_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_root_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_root_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_root_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_root_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_root_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_root_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_root_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool NO
fi

#####----- Rule: os_safari_advertising_privacy_protection_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles -P -o stdout | /usr/bin/grep -c '"WebKitPreferences.privateClickMeasurementEnabled" = 1' | /usr/bin/awk '{ if ($1 >= 1) {print "1"} else {print "0"}}'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_advertising_privacy_protection_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_advertising_privacy_protection_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_safari_advertising_privacy_protection_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_safari_advertising_privacy_protection_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_safari_advertising_privacy_protection_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_safari_advertising_privacy_protection_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_safari_advertising_privacy_protection_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_safari_advertising_privacy_protection_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_safari_advertising_privacy_protection_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_safari_advertising_privacy_protection_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_advertising_privacy_protection_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_safari_advertising_privacy_protection_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_advertising_privacy_protection_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_safari_advertising_privacy_protection_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_safari_advertising_privacy_protection_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_advertising_privacy_protection_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_safari_advertising_privacy_protection_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_advertising_privacy_protection_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_safari_advertising_privacy_protection_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_safari_advertising_privacy_protection_enable -dict-add finding -bool NO
fi

#####----- Rule: os_safari_open_safe_downloads_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles -P -o stdout | /usr/bin/grep -c 'AutoOpenSafeDownloads = 0' | /usr/bin/awk '{ if ($1 >= 1) {print "1"} else {print "0"}}'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_open_safe_downloads_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_open_safe_downloads_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_safari_open_safe_downloads_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_safari_open_safe_downloads_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_safari_open_safe_downloads_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_safari_open_safe_downloads_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_safari_open_safe_downloads_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_open_safe_downloads_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_open_safe_downloads_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_safari_open_safe_downloads_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_open_safe_downloads_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_open_safe_downloads_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_safari_open_safe_downloads_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_safari_open_safe_downloads_disable -dict-add finding -bool NO
fi

#####----- Rule: os_safari_prevent_cross-site_tracking_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles -P -o stdout | /usr/bin/grep -cE '"WebKitPreferences.storageBlockingPolicy" = 1|"WebKitStorageBlockingPolicy" = 1|"BlockStoragePolicy" =2' | /usr/bin/awk '{ if ($1 >= 1) {print "1"} else {print "0"}}'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_prevent_cross-site_tracking_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_prevent_cross-site_tracking_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_safari_prevent_cross-site_tracking_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_safari_prevent_cross-site_tracking_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_safari_prevent_cross-site_tracking_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_safari_prevent_cross-site_tracking_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_safari_prevent_cross-site_tracking_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_safari_prevent_cross-site_tracking_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_safari_prevent_cross-site_tracking_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_safari_prevent_cross-site_tracking_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_prevent_cross-site_tracking_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_safari_prevent_cross-site_tracking_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_prevent_cross-site_tracking_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_safari_prevent_cross-site_tracking_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_safari_prevent_cross-site_tracking_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_prevent_cross-site_tracking_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_safari_prevent_cross-site_tracking_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_prevent_cross-site_tracking_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_safari_prevent_cross-site_tracking_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_safari_prevent_cross-site_tracking_enable -dict-add finding -bool NO
fi

#####----- Rule: os_safari_show_full_website_address_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles -P -o stdout | /usr/bin/grep -c 'ShowFullURLInSmartSearchField = 1' | /usr/bin/awk '{ if ($1 >= 1) {print "1"} else {print "0"}}'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_show_full_website_address_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_show_full_website_address_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_safari_show_full_website_address_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_safari_show_full_website_address_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_safari_show_full_website_address_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_safari_show_full_website_address_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_safari_show_full_website_address_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_safari_show_full_website_address_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_safari_show_full_website_address_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_safari_show_full_website_address_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_show_full_website_address_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_safari_show_full_website_address_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_show_full_website_address_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_safari_show_full_website_address_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_safari_show_full_website_address_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_show_full_website_address_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_safari_show_full_website_address_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_show_full_website_address_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_safari_show_full_website_address_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_safari_show_full_website_address_enable -dict-add finding -bool NO
fi

#####----- Rule: os_safari_show_status_bar_enabled -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles -P -o stdout | /usr/bin/grep -c 'ShowOverlayStatusBar = 1' | /usr/bin/awk '{ if ($1 >= 1) {print "1"} else {print "0"}}'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_show_status_bar_enabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_show_status_bar_enabled'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_safari_show_status_bar_enabled" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_safari_show_status_bar_enabled passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_safari_show_status_bar_enabled -dict-add finding -bool NO
        if [[ ! "$customref" == "os_safari_show_status_bar_enabled" ]]; then
            /usr/bin/defaults write "$audit_plist" os_safari_show_status_bar_enabled -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_safari_show_status_bar_enabled passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_safari_show_status_bar_enabled failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_safari_show_status_bar_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_show_status_bar_enabled" ]]; then
                /usr/bin/defaults write "$audit_plist" os_safari_show_status_bar_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_show_status_bar_enabled failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_safari_show_status_bar_enabled failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_safari_show_status_bar_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_show_status_bar_enabled" ]]; then
              /usr/bin/defaults write "$audit_plist" os_safari_show_status_bar_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_show_status_bar_enabled failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_safari_show_status_bar_enabled does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_safari_show_status_bar_enabled -dict-add finding -bool NO
fi

#####----- Rule: os_safari_warn_fraudulent_website_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles -P -o stdout | /usr/bin/grep -c 'WarnAboutFraudulentWebsites = 1' | /usr/bin/awk '{ if ($1 >= 1) {print "1"} else {print "0"}}'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_warn_fraudulent_website_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_safari_warn_fraudulent_website_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_safari_warn_fraudulent_website_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_safari_warn_fraudulent_website_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_safari_warn_fraudulent_website_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_safari_warn_fraudulent_website_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_safari_warn_fraudulent_website_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_safari_warn_fraudulent_website_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_safari_warn_fraudulent_website_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_safari_warn_fraudulent_website_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_warn_fraudulent_website_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_safari_warn_fraudulent_website_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_warn_fraudulent_website_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_safari_warn_fraudulent_website_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_safari_warn_fraudulent_website_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_safari_warn_fraudulent_website_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_safari_warn_fraudulent_website_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_safari_warn_fraudulent_website_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_safari_warn_fraudulent_website_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_safari_warn_fraudulent_website_enable -dict-add finding -bool NO
fi

#####----- Rule: os_show_filename_extensions_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults read .GlobalPreferences AppleShowAllExtensions 2>/dev/null
)
    # expected result {'boolean': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_show_filename_extensions_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_show_filename_extensions_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_show_filename_extensions_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_show_filename_extensions_enable passed (Result: $result_value, Expected: \"{'boolean': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_show_filename_extensions_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_show_filename_extensions_enable passed (Result: $result_value, Expected: "{'boolean': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_show_filename_extensions_enable failed (Result: $result_value, Expected: \"{'boolean': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_show_filename_extensions_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_show_filename_extensions_enable failed (Result: $result_value, Expected: "{'boolean': 1}")"
        else
            logmessage "os_show_filename_extensions_enable failed (Result: $result_value, Expected: \"{'boolean': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_show_filename_extensions_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_show_filename_extensions_enable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_show_filename_extensions_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_show_filename_extensions_enable -dict-add finding -bool NO
fi

#####----- Rule: os_sip_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-3
# * AU-9, AU-9(3)
# * CM-5, CM-5(6)
# * SC-4
# * SI-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/csrutil status | /usr/bin/grep -c 'System Integrity Protection status: enabled.'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sip_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sip_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sip_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_sip_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sip_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_sip_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sip_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sip_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_sip_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sip_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sip_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool NO
fi

#####----- Rule: os_software_update_deferral -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let timeout = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('enforcedSoftwareUpdateDelay')) || 0
  if ( timeout <= 30 ) {
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_software_update_deferral'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_software_update_deferral'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_software_update_deferral" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_software_update_deferral passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add finding -bool NO
        if [[ ! "$customref" == "os_software_update_deferral" ]]; then
            /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_software_update_deferral passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_software_update_deferral failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add finding -bool YES
            if [[ ! "$customref" == "os_software_update_deferral" ]]; then
                /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_software_update_deferral failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_software_update_deferral failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add finding -bool YES
            if [[ ! "$customref" == "os_software_update_deferral" ]]; then
              /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_software_update_deferral failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_software_update_deferral does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_software_update_deferral -dict-add finding -bool NO
fi

#####----- Rule: os_sudo_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/sudo /usr/bin/sudo -V | /usr/bin/grep -c "Authentication timestamp timeout: 0.0 minutes"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sudo_timeout_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sudo_timeout_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sudo_timeout_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_sudo_timeout_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sudo_timeout_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_sudo_timeout_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sudo_timeout_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sudo_timeout_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_sudo_timeout_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_sudo_timeout_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sudo_timeout_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_sudo_timeout_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sudo_timeout_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool NO
fi

#####----- Rule: os_sudoers_timestamp_type_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-5(1)
# * IA-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/sudo /usr/bin/sudo -V | /usr/bin/awk -F": " '/Type of authentication timestamp record/{print $2}'
)
    # expected result {'string': 'tty'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sudoers_timestamp_type_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "tty" ]]; then
        logmessage "os_sudoers_timestamp_type_configure passed (Result: $result_value, Expected: \"{'string': 'tty'}\")"
        /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sudoers_timestamp_type_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_sudoers_timestamp_type_configure passed (Result: $result_value, Expected: "{'string': 'tty'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: \"{'string': 'tty'}\")"
            /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sudoers_timestamp_type_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: "{'string': 'tty'}")"
        else
            logmessage "os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: \"{'string': 'tty'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sudoers_timestamp_type_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: "{'string': 'tty'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sudoers_timestamp_type_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool NO
fi

#####----- Rule: os_system_wide_applications_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/find /Applications -iname "*\.app" -type d -perm -2 -ls | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_system_wide_applications_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_system_wide_applications_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_system_wide_applications_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_system_wide_applications_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_system_wide_applications_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_system_wide_applications_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_system_wide_applications_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_system_wide_applications_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_system_wide_applications_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_system_wide_applications_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_system_wide_applications_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_system_wide_applications_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_system_wide_applications_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_system_wide_applications_configure -dict-add finding -bool NO
fi

#####----- Rule: os_terminal_secure_keyboard_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.Terminal')\
.objectForKey('SecureKeyboardEntry').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_terminal_secure_keyboard_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_terminal_secure_keyboard_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_terminal_secure_keyboard_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_terminal_secure_keyboard_enable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_terminal_secure_keyboard_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_terminal_secure_keyboard_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_terminal_secure_keyboard_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_terminal_secure_keyboard_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_terminal_secure_keyboard_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_terminal_secure_keyboard_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_terminal_secure_keyboard_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_terminal_secure_keyboard_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_terminal_secure_keyboard_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_terminal_secure_keyboard_enable -dict-add finding -bool NO
fi

#####----- Rule: os_time_server_enabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12(1)
# * SC-45(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl list | /usr/bin/grep -c com.apple.timed
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_time_server_enabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_time_server_enabled'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_time_server_enabled" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_time_server_enabled passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add finding -bool NO
        if [[ ! "$customref" == "os_time_server_enabled" ]]; then
            /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_time_server_enabled passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_time_server_enabled failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "os_time_server_enabled" ]]; then
                /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_time_server_enabled failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_time_server_enabled failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "os_time_server_enabled" ]]; then
              /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_time_server_enabled failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_time_server_enabled does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add finding -bool NO
fi

#####----- Rule: os_unlock_active_user_session_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/security authorizationdb read system.login.screensaver 2>&1 | /usr/bin/grep -c '<string>authenticate-session-owner</string>'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_unlock_active_user_session_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_unlock_active_user_session_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_unlock_active_user_session_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_unlock_active_user_session_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_unlock_active_user_session_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_unlock_active_user_session_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_unlock_active_user_session_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_unlock_active_user_session_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_unlock_active_user_session_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool NO
fi

#####----- Rule: os_world_writable_system_folder_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/find /System/Volumes/Data/System -type d -perm -2 -ls | /usr/bin/grep -vE "downloadDir|locks" | /usr/bin/wc -l | /usr/bin/xargs
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_world_writable_system_folder_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_world_writable_system_folder_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_world_writable_system_folder_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_world_writable_system_folder_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_world_writable_system_folder_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - os_world_writable_system_folder_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_world_writable_system_folder_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_world_writable_system_folder_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_world_writable_system_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_world_writable_system_folder_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_world_writable_system_folder_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - os_world_writable_system_folder_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_world_writable_system_folder_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_world_writable_system_folder_configure -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_account_lockout_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyAttributeMaximumFailedAuthentications"]/following-sibling::integer[1]/text()' - | /usr/bin/awk '{ if ($1 <= 5) {print "yes"} else {print "no"}}'
)
    # expected result {'string': 'yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_account_lockout_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_account_lockout_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_account_lockout_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "yes" ]]; then
        logmessage "pwpolicy_account_lockout_enforce passed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_account_lockout_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_account_lockout_enforce passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_account_lockout_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_lockout_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_account_lockout_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            logmessage "pwpolicy_account_lockout_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_lockout_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_account_lockout_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_account_lockout_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_account_lockout_timeout_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="autoEnableInSeconds"]/following-sibling::integer[1]/text()' - | /usr/bin/awk '{ if ($1/60 >= 15 ) {print "yes"} else {print "no"}}'
)
    # expected result {'string': 'yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_account_lockout_timeout_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_account_lockout_timeout_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_account_lockout_timeout_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "yes" ]]; then
        logmessage "pwpolicy_account_lockout_timeout_enforce passed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_account_lockout_timeout_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_account_lockout_timeout_enforce passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_account_lockout_timeout_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_lockout_timeout_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_account_lockout_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            logmessage "pwpolicy_account_lockout_timeout_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_lockout_timeout_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_account_lockout_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_account_lockout_timeout_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_history_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyAttributePasswordHistoryDepth"]/following-sibling::*[1]/text()' - | /usr/bin/awk '{ if ($1 >= 15 ) {print "yes"} else {print "no"}}'
)
    # expected result {'string': 'yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_history_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_history_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_history_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "yes" ]]; then
        logmessage "pwpolicy_history_enforce passed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_history_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_history_enforce passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_history_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_history_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_history_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            logmessage "pwpolicy_history_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_history_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_history_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_history_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_max_lifetime_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyAttributeExpiresEveryNDays"]/following-sibling::*[1]/text()' -
)
    # expected result {'integer': 365}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_max_lifetime_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_max_lifetime_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_max_lifetime_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "365" ]]; then
        logmessage "pwpolicy_max_lifetime_enforce passed (Result: $result_value, Expected: \"{'integer': 365}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_max_lifetime_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_max_lifetime_enforce passed (Result: $result_value, Expected: "{'integer': 365}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_max_lifetime_enforce failed (Result: $result_value, Expected: \"{'integer': 365}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_max_lifetime_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_max_lifetime_enforce failed (Result: $result_value, Expected: "{'integer': 365}")"
        else
            logmessage "pwpolicy_max_lifetime_enforce failed (Result: $result_value, Expected: \"{'integer': 365}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_max_lifetime_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_max_lifetime_enforce failed (Result: $result_value, Expected: "{'integer': 365}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_max_lifetime_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_minimum_length_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath 'boolean(//*[contains(text(),"policyAttributePassword matches '\''.{15,}'\''")])' -
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_minimum_length_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('pwpolicy_minimum_length_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_minimum_length_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "pwpolicy_minimum_length_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_minimum_length_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_minimum_length_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_minimum_length_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_minimum_length_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_minimum_length_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "pwpolicy_minimum_length_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_minimum_length_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - pwpolicy_minimum_length_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_minimum_length_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_airplay_receiver_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowAirPlayIncomingRequests').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_airplay_receiver_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_airplay_receiver_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_airplay_receiver_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "system_settings_airplay_receiver_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_airplay_receiver_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_airplay_receiver_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_airplay_receiver_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_airplay_receiver_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_airplay_receiver_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_airplay_receiver_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_airplay_receiver_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_airplay_receiver_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_airplay_receiver_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_automatic_login_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2
# * IA-5(13)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('com.apple.login.mcx.DisableAutoLoginClient').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_automatic_login_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_automatic_login_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_automatic_login_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_automatic_login_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_automatic_login_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_automatic_login_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_automatic_login_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_automatic_login_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_automatic_login_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_automatic_login_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_automatic_login_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_bluetooth_menu_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.controlcenter')\
.objectForKey('Bluetooth').js
EOS
)
    # expected result {'integer': 18}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_bluetooth_menu_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_bluetooth_menu_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_bluetooth_menu_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "18" ]]; then
        logmessage "system_settings_bluetooth_menu_enable passed (Result: $result_value, Expected: \"{'integer': 18}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_menu_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_bluetooth_menu_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_menu_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_bluetooth_menu_enable passed (Result: $result_value, Expected: "{'integer': 18}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_bluetooth_menu_enable failed (Result: $result_value, Expected: \"{'integer': 18}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_menu_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_menu_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_menu_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_bluetooth_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}")"
        else
            logmessage "system_settings_bluetooth_menu_enable failed (Result: $result_value, Expected: \"{'integer': 18}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_menu_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_menu_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_menu_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_bluetooth_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_bluetooth_menu_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_menu_enable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_bluetooth_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-18(4)
# * AC-3
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost read com.apple.Bluetooth PrefKeyServicesEnabled
)
    # expected result {'boolean': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_bluetooth_sharing_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "system_settings_bluetooth_sharing_disable passed (Result: $result_value, Expected: \"{'boolean': 0}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_bluetooth_sharing_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_bluetooth_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}")"
        else
            logmessage "system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_bluetooth_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_cd_dvd_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pgrep -q ODSAgent; /bin/echo $?
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_cd_dvd_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_cd_dvd_sharing_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_cd_dvd_sharing_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_cd_dvd_sharing_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_cd_dvd_sharing_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_cd_dvd_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_cd_dvd_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_cd_dvd_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_cd_dvd_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_cd_dvd_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_cd_dvd_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_cd_dvd_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_cd_dvd_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_critical_update_install_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-2
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('CriticalUpdateInstall').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_critical_update_install_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_critical_update_install_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_critical_update_install_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_critical_update_install_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_critical_update_install_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_critical_update_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_critical_update_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_critical_update_install_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_critical_update_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_critical_update_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_critical_update_install_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_critical_update_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_critical_update_install_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_filevault_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * SC-28, SC-28(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(dontAllowDisable=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('dontAllowFDEDisable').js
EOS
)
fileVault=$(/usr/bin/fdesetup status | /usr/bin/grep -c "FileVault is On.")
if [[ "$dontAllowDisable" == "true" ]] && [[ "$fileVault" == 1 ]]; then
  echo "1"
else
  echo "0"
fi
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_filevault_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_filevault_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_filevault_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_filevault_enforce passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_filevault_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_filevault_enforce passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_filevault_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_filevault_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_filevault_enforce failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_filevault_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_filevault_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_filevault_enforce failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_filevault_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_firewall_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-4
# * CM-7, CM-7(1)
# * SC-7, SC-7(12)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(profile="$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.firewall')\
.objectForKey('EnableFirewall').js
EOS
)"

plist="$(/usr/bin/defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)"

if [[ "$profile" == "true" ]] && [[ "$plist" =~ [1,2] ]]; then
  echo "true"
else
  echo "false"
fi
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_firewall_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_firewall_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_firewall_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_firewall_enable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_firewall_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_firewall_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_firewall_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_firewall_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_firewall_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_firewall_stealth_mode_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
# * SC-7, SC-7(16)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(profile="$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.firewall')\
.objectForKey('EnableStealthMode').js
EOS
)"

plist=$(/usr/bin/defaults read /Library/Preferences/com.apple.alf stealthenabled 2>/dev/null)

if [[ "$profile" == "true" ]] && [[ $plist == 1 ]]; then
  echo "true"
else
  echo "false"
fi
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_firewall_stealth_mode_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_firewall_stealth_mode_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_firewall_stealth_mode_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_firewall_stealth_mode_enable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_firewall_stealth_mode_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_firewall_stealth_mode_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_firewall_stealth_mode_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_stealth_mode_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_firewall_stealth_mode_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_firewall_stealth_mode_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_stealth_mode_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_firewall_stealth_mode_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_firewall_stealth_mode_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_guest_access_smb_disable -----#####
## Addresses the following NIST 800-53 controls: N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/defaults read /Library/Preferences/SystemConfiguration/com.apple.smb.server AllowGuestAccess
)
    # expected result {'boolean': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_guest_access_smb_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_guest_access_smb_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_guest_access_smb_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "system_settings_guest_access_smb_disable passed (Result: $result_value, Expected: \"{'boolean': 0}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_guest_access_smb_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_guest_access_smb_disable passed (Result: $result_value, Expected: "{'boolean': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_guest_access_smb_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_access_smb_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_guest_access_smb_disable failed (Result: $result_value, Expected: "{'boolean': 0}")"
        else
            logmessage "system_settings_guest_access_smb_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_access_smb_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_guest_access_smb_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_guest_access_smb_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_guest_account_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2, AC-2(9)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let pref1 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('DisableGuestAccount'))
  let pref2 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('EnableGuestAccount'))
  if ( pref1 == true && pref2 == false ) {
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_guest_account_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_guest_account_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_guest_account_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_guest_account_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_guest_account_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_guest_account_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_guest_account_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_account_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_guest_account_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_account_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_guest_account_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_install_macos_updates_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('AutomaticallyInstallMacOSUpdates').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_install_macos_updates_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_install_macos_updates_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_install_macos_updates_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_install_macos_updates_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_install_macos_updates_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_install_macos_updates_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_install_macos_updates_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_install_macos_updates_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_install_macos_updates_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_install_macos_updates_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_install_macos_updates_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_install_macos_updates_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_install_macos_updates_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_install_macos_updates_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_install_macos_updates_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_install_macos_updates_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_install_macos_updates_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_install_macos_updates_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_install_macos_updates_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_install_macos_updates_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_internet_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * AC-4
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('forceInternetSharingOff').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_internet_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_internet_sharing_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_internet_sharing_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_internet_sharing_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_internet_sharing_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_internet_sharing_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_internet_sharing_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_internet_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_internet_sharing_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_internet_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_internet_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_loginwindow_loginwindowtext_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS | /usr/bin/base64
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('LoginwindowText').js
EOS
)
    # expected result {'base64': 'VGhpcyBjb21wdXRlciBpcyBjb21wbGlhbnQgd2l0aCBDSVMgTGV2ZWwgMQo='}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_loginwindow_loginwindowtext_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_loginwindow_loginwindowtext_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_loginwindow_loginwindowtext_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "VGhpcyBjb21wdXRlciBpcyBjb21wbGlhbnQgd2l0aCBDSVMgTGV2ZWwgMQo=" ]]; then
        logmessage "system_settings_loginwindow_loginwindowtext_enable passed (Result: $result_value, Expected: \"{'base64': 'VGhpcyBjb21wdXRlciBpcyBjb21wbGlhbnQgd2l0aCBDSVMgTGV2ZWwgMQo='}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_loginwindowtext_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_loginwindow_loginwindowtext_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_loginwindowtext_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_loginwindow_loginwindowtext_enable passed (Result: $result_value, Expected: "{'base64': 'VGhpcyBjb21wdXRlciBpcyBjb21wbGlhbnQgd2l0aCBDSVMgTGV2ZWwgMQo='}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_loginwindow_loginwindowtext_enable failed (Result: $result_value, Expected: \"{'base64': 'VGhpcyBjb21wdXRlciBpcyBjb21wbGlhbnQgd2l0aCBDSVMgTGV2ZWwgMQo='}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_loginwindowtext_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_loginwindow_loginwindowtext_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_loginwindowtext_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_loginwindow_loginwindowtext_enable failed (Result: $result_value, Expected: "{'base64': 'VGhpcyBjb21wdXRlciBpcyBjb21wbGlhbnQgd2l0aCBDSVMgTGV2ZWwgMQo='}")"
        else
            logmessage "system_settings_loginwindow_loginwindowtext_enable failed (Result: $result_value, Expected: \"{'base64': 'VGhpcyBjb21wdXRlciBpcyBjb21wbGlhbnQgd2l0aCBDSVMgTGV2ZWwgMQo='}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_loginwindowtext_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_loginwindow_loginwindowtext_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_loginwindowtext_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_loginwindow_loginwindowtext_enable failed (Result: $result_value, Expected: "{'base64': 'VGhpcyBjb21wdXRlciBpcyBjb21wbGlhbnQgd2l0aCBDSVMgTGV2ZWwgMQo='}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_loginwindow_loginwindowtext_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_loginwindowtext_enable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_loginwindow_prompt_username_password_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('SHOWFULLNAME').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_loginwindow_prompt_username_password_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_loginwindow_prompt_username_password_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_loginwindow_prompt_username_password_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_loginwindow_prompt_username_password_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_loginwindow_prompt_username_password_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_loginwindow_prompt_username_password_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_loginwindow_prompt_username_password_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_loginwindow_prompt_username_password_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_loginwindow_prompt_username_password_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_password_hints_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-6
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('RetriesUntilHint').js
EOS
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_password_hints_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_password_hints_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_password_hints_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "system_settings_password_hints_disable passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_password_hints_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_password_hints_disable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_password_hints_disable failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_password_hints_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_password_hints_disable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "system_settings_password_hints_disable failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_password_hints_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_password_hints_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_password_hints_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_personalized_advertising_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowApplePersonalizedAdvertising').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_personalized_advertising_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_personalized_advertising_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_personalized_advertising_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "system_settings_personalized_advertising_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_personalized_advertising_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_personalized_advertising_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_personalized_advertising_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_personalized_advertising_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_personalized_advertising_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_printer_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/cupsctl | /usr/bin/grep -c "_share_printers=0"
)
    # expected result {'boolean': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_printer_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_printer_sharing_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_printer_sharing_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_printer_sharing_disable passed (Result: $result_value, Expected: \"{'boolean': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_printer_sharing_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_printer_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_printer_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_printer_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_printer_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 1}")"
        else
            logmessage "system_settings_printer_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_printer_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_printer_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_printer_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_rae_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.AEServer" => disabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_rae_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_rae_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_rae_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_rae_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_rae_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_rae_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_rae_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_rae_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_rae_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_rae_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_rae_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_remote_management_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/libexec/mdmclient QuerySecurityInfo | /usr/bin/grep -c "RemoteDesktopEnabled = 0"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_remote_management_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_remote_management_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_remote_management_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_remote_management_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_remote_management_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_remote_management_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_remote_management_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_remote_management_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_remote_management_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_remote_management_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_remote_management_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_remote_management_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_remote_management_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_screen_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.screensharing" => disabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_screen_sharing_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_screen_sharing_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_screen_sharing_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screen_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_screen_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screen_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_screen_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screen_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_screen_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_screensaver_ask_for_password_delay_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let delay = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.screensaver')\
.objectForKey('askForPasswordDelay'))
  if ( delay <= 5 ) {
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_screensaver_ask_for_password_delay_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_screensaver_ask_for_password_delay_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_screensaver_ask_for_password_delay_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_screensaver_ask_for_password_delay_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_screensaver_ask_for_password_delay_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screensaver_ask_for_password_delay_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_ask_for_password_delay_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_ask_for_password_delay_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_screensaver_ask_for_password_delay_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_screensaver_timeout_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11
# * IA-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let timeout = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.screensaver')\
.objectForKey('idleTime'))
  if ( timeout <= 1200 ) {
    return("true")
  } else {
    return("false")
  }
}
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_screensaver_timeout_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_screensaver_timeout_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_screensaver_timeout_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_screensaver_timeout_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_screensaver_timeout_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screensaver_timeout_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_screensaver_timeout_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_timeout_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screensaver_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_screensaver_timeout_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_timeout_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_screensaver_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_screensaver_timeout_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_siri_listen_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/sudo /usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.Siri')\
.objectForKey('VoiceTriggerUserEnabled').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_siri_listen_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_siri_listen_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_siri_listen_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "system_settings_siri_listen_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_siri_listen_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_siri_listen_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_siri_listen_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_siri_listen_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_siri_listen_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_siri_listen_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_siri_listen_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_siri_listen_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_siri_listen_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_siri_listen_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_siri_listen_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_siri_listen_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_siri_listen_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_siri_listen_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_siri_listen_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_siri_listen_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_smbd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.smbd" => disabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_smbd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_smbd_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_smbd_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_smbd_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_smbd_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_smbd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_smbd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_smbd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_smbd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_smbd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_smbd_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_software_update_app_update_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('AutomaticallyInstallAppUpdates').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_software_update_app_update_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_software_update_app_update_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_software_update_app_update_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_software_update_app_update_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_software_update_app_update_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_software_update_app_update_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_app_update_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_app_update_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_software_update_app_update_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_app_update_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_software_update_app_update_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_software_update_app_update_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_app_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_software_update_app_update_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_app_update_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_software_update_app_update_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_software_update_app_update_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_app_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_software_update_app_update_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_software_update_app_update_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_software_update_download_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('AutomaticDownload').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_software_update_download_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_software_update_download_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_software_update_download_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_software_update_download_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_software_update_download_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_software_update_download_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_download_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_download_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_software_update_download_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_download_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_software_update_download_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_software_update_download_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_download_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_software_update_download_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_download_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_software_update_download_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_software_update_download_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_download_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_software_update_download_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_software_update_download_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_software_update_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-2(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SoftwareUpdate')\
.objectForKey('AutomaticCheckEnabled').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_software_update_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_software_update_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_software_update_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_software_update_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_software_update_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_software_update_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_software_update_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_software_update_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_software_update_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_software_update_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_software_update_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_software_update_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_software_update_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_software_update_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_software_update_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_software_update_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_softwareupdate_current -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(softwareupdate_date_epoch=$(/bin/date -j -f "%Y-%m-%d" "$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastFullSuccessfulDate | /usr/bin/awk '{print $1}')" "+%s")
thirty_days_epoch=$(/bin/date -v -30d "+%s")
if [[ $softwareupdate_date_epoch -lt $thirty_days_epoch ]]; then
  /bin/echo "0"
else
  /bin/echo "1"
fi
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_softwareupdate_current'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_softwareupdate_current'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_softwareupdate_current" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_softwareupdate_current passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_softwareupdate_current -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_softwareupdate_current" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_softwareupdate_current -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_softwareupdate_current passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_softwareupdate_current failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_softwareupdate_current -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_softwareupdate_current" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_softwareupdate_current -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_softwareupdate_current failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_softwareupdate_current failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_softwareupdate_current -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_softwareupdate_current" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_softwareupdate_current -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_softwareupdate_current failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_softwareupdate_current does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_softwareupdate_current -dict-add finding -bool NO
fi

#####----- Rule: system_settings_ssh_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.openssh.sshd" => disabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_ssh_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_ssh_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_ssh_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_ssh_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_ssh_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_ssh_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_ssh_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_ssh_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_ssh_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_ssh_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_ssh_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_ssh_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_ssh_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_system_wide_preferences_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6, AC-6(1), AC-6(2)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(authDBs=("system.preferences" "system.preferences.energysaver" "system.preferences.network" "system.preferences.printing" "system.preferences.sharing" "system.preferences.softwareupdate" "system.preferences.startupdisk" "system.preferences.timemachine")
result="1"
for section in ${authDBs[@]}; do
  if [[ $(/usr/bin/security -q authorizationdb read "$section" | /usr/bin/xmllint -xpath 'name(//*[contains(text(), "shared")]/following-sibling::*[1])' -) != "false" ]]; then
    result="0"
  fi
  if [[ $(/usr/bin/security -q authorizationdb read "$section" | /usr/bin/xmllint -xpath '//*[contains(text(), "group")]/following-sibling::*[1]/text()' - ) != "admin" ]]; then
    result="0"
  fi
  if [[ $(/usr/bin/security -q authorizationdb read "$section" | /usr/bin/xmllint -xpath 'name(//*[contains(text(), "authenticate-user")]/following-sibling::*[1])' -) != "true" ]]; then
    result="0"
  fi
  if [[ $(/usr/bin/security -q authorizationdb read "$section" | /usr/bin/xmllint -xpath 'name(//*[contains(text(), "session-owner")]/following-sibling::*[1])' -) != "false" ]]; then
    result="0"
  fi
done
echo $result
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_system_wide_preferences_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_system_wide_preferences_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_system_wide_preferences_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_system_wide_preferences_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_system_wide_preferences_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_system_wide_preferences_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_system_wide_preferences_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool NO
fi

#####----- Rule: system_settings_time_machine_encrypted_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(error_count=0
for tm in $(/usr/bin/tmutil destinationinfo 2>/dev/null| /usr/bin/awk -F': ' '/Name/{print $2}'); do
  tmMounted=$(/usr/sbin/diskutil info "${tm}" 2>/dev/null | /usr/bin/awk '/Mounted/{print $2}')
  tmEncrypted=$(/usr/sbin/diskutil info "${tm}" 2>/dev/null | /usr/bin/awk '/FileVault/{print $2}')
  if [[ "$tmMounted" = "Yes" && "$tmEncrypted" = "No" ]]; then
      ((error_count++))
  fi
done
echo "$error_count"
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_time_machine_encrypted_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_time_machine_encrypted_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_time_machine_encrypted_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "system_settings_time_machine_encrypted_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_time_machine_encrypted_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_time_machine_encrypted_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_time_machine_encrypted_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_machine_encrypted_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_time_machine_encrypted_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_machine_encrypted_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_machine_encrypted_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_time_machine_encrypted_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_machine_encrypted_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "system_settings_time_machine_encrypted_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_machine_encrypted_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_machine_encrypted_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_time_machine_encrypted_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_machine_encrypted_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_time_machine_encrypted_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_time_machine_encrypted_configure -dict-add finding -bool NO
fi

#####----- Rule: system_settings_time_server_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12(1)
# * SC-45(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCX')\
.objectForKey('timeServer').js
EOS
)
    # expected result {'string': 'time.apple.com'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_time_server_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_time_server_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_time_server_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "time.apple.com" ]]; then
        logmessage "system_settings_time_server_configure passed (Result: $result_value, Expected: \"{'string': 'time.apple.com'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_time_server_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_server_configure passed (Result: $result_value, Expected: "{'string': 'time.apple.com'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_time_server_configure failed (Result: $result_value, Expected: \"{'string': 'time.apple.com'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_server_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_server_configure failed (Result: $result_value, Expected: "{'string': 'time.apple.com'}")"
        else
            logmessage "system_settings_time_server_configure failed (Result: $result_value, Expected: \"{'string': 'time.apple.com'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_server_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_server_configure failed (Result: $result_value, Expected: "{'string': 'time.apple.com'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_time_server_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add finding -bool NO
fi

#####----- Rule: system_settings_time_server_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12(1)
# * SC-45(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.timed')\
.objectForKey('TMAutomaticTimeOnlyEnabled').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_time_server_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_time_server_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_time_server_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_time_server_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_time_server_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_server_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_time_server_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_server_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_server_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_time_server_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_server_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_time_server_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_time_server_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_wake_network_access_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pmset -g custom | /usr/bin/awk '/womp/ { sum+=$2 } END {print sum}'
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_wake_network_access_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_wake_network_access_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_wake_network_access_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "system_settings_wake_network_access_disable passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_wake_network_access_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_wake_network_access_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_wake_network_access_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_wake_network_access_disable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_wake_network_access_disable failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_wake_network_access_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_wake_network_access_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_wake_network_access_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_wake_network_access_disable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "system_settings_wake_network_access_disable failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_wake_network_access_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_wake_network_access_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_wake_network_access_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_wake_network_access_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_wake_network_access_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_wake_network_access_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_wifi_menu_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.controlcenter')\
.objectForKey('WiFi').js
EOS
)
    # expected result {'integer': 18}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_wifi_menu_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_wifi_menu_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_wifi_menu_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "18" ]]; then
        logmessage "system_settings_wifi_menu_enable passed (Result: $result_value, Expected: \"{'integer': 18}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_wifi_menu_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_wifi_menu_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_wifi_menu_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cis_lvl1 - system_settings_wifi_menu_enable passed (Result: $result_value, Expected: "{'integer': 18}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_wifi_menu_enable failed (Result: $result_value, Expected: \"{'integer': 18}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_wifi_menu_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_wifi_menu_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_wifi_menu_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_wifi_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}")"
        else
            logmessage "system_settings_wifi_menu_enable failed (Result: $result_value, Expected: \"{'integer': 18}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_wifi_menu_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_wifi_menu_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_wifi_menu_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cis_lvl1 - system_settings_wifi_menu_enable failed (Result: $result_value, Expected: "{'integer': 18}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_wifi_menu_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_wifi_menu_enable -dict-add finding -bool NO
fi

lastComplianceScan=$(defaults read "$audit_plist" lastComplianceCheck)
echo "Results written to $audit_plist"

if [[ ! $check ]] && [[ ! $cfc ]];then
    pause
fi

} 2>/dev/null

run_fix(){

if [[ ! -e "$audit_plist" ]]; then
    echo "Audit plist doesn't exist, please run Audit Check First" | tee -a "$audit_log"

    if [[ ! $fix ]]; then
        pause
        show_menus
        read_options
    else
        exit 1
    fi
fi

if [[ ! $fix ]] && [[ ! $cfc ]]; then
    ask 'THE SOFTWARE IS PROVIDED "AS IS" WITHOUT ANY WARRANTY OF ANY KIND, EITHER EXPRESSED, IMPLIED, OR STATUTORY, INCLUDING, BUT NOT LIMITED TO, ANY WARRANTY THAT THE SOFTWARE WILL CONFORM TO SPECIFICATIONS, ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND FREEDOM FROM INFRINGEMENT, AND ANY WARRANTY THAT THE DOCUMENTATION WILL CONFORM TO THE SOFTWARE, OR ANY WARRANTY THAT THE SOFTWARE WILL BE ERROR FREE.  IN NO EVENT SHALL NIST BE LIABLE FOR ANY DAMAGES, INCLUDING, BUT NOT LIMITED TO, DIRECT, INDIRECT, SPECIAL OR CONSEQUENTIAL DAMAGES, ARISING OUT OF, RESULTING FROM, OR IN ANY WAY CONNECTED WITH THIS SOFTWARE, WHETHER OR NOT BASED UPON WARRANTY, CONTRACT, TORT, OR OTHERWISE, WHETHER OR NOT INJURY WAS SUSTAINED BY PERSONS OR PROPERTY OR OTHERWISE, AND WHETHER OR NOT LOSS WAS SUSTAINED FROM, OR AROSE OUT OF THE RESULTS OF, OR USE OF, THE SOFTWARE OR SERVICES PROVIDED HEREUNDER. WOULD YOU LIKE TO CONTINUE? ' N

    if [[ $? != 0 ]]; then
        show_menus
        read_options
    fi
fi

# append to existing logfile
echo "$(date -u) Beginning remediation of non-compliant settings" >> "$audit_log"

# remove uchg on audit_control
/usr/bin/chflags nouchg /etc/security/audit_control

# run mcxrefresh
/usr/bin/mcxrefresh -u $CURR_USER_UID


    
#####----- Rule: audit_acls_files_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_acls_files_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_acls_files_configure'))["exempt_reason"]
EOS
)

audit_acls_files_configure_audit_score=$($plb -c "print audit_acls_files_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_acls_files_configure_audit_score == "true" ]]; then
        ask 'audit_acls_files_configure - Run the command(s)-> /bin/chmod -RN /var/audit ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_acls_files_configure ..."
            /bin/chmod -RN /var/audit
        fi
    else
        logmessage "Settings for: audit_acls_files_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_acls_files_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_acls_folders_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_acls_folders_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_acls_folders_configure'))["exempt_reason"]
EOS
)

audit_acls_folders_configure_audit_score=$($plb -c "print audit_acls_folders_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_acls_folders_configure_audit_score == "true" ]]; then
        ask 'audit_acls_folders_configure - Run the command(s)-> /bin/chmod -N /var/audit ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_acls_folders_configure ..."
            /bin/chmod -N /var/audit
        fi
    else
        logmessage "Settings for: audit_acls_folders_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_acls_folders_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_auditd_enabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12, AU-12(1), AU-12(3)
# * AU-14(1)
# * AU-3, AU-3(1)
# * AU-8
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_auditd_enabled'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_auditd_enabled'))["exempt_reason"]
EOS
)

audit_auditd_enabled_audit_score=$($plb -c "print audit_auditd_enabled:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_auditd_enabled_audit_score == "true" ]]; then
        ask 'audit_auditd_enabled - Run the command(s)-> if [[ ! -e /etc/security/audit_control ]] && [[ -e /etc/security/audit_control.example ]];then
  /bin/cp /etc/security/audit_control.example /etc/security/audit_control
fi

/bin/launchctl enable system/com.apple.auditd
/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.auditd.plist
/usr/sbin/audit -i ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_auditd_enabled ..."
            if [[ ! -e /etc/security/audit_control ]] && [[ -e /etc/security/audit_control.example ]];then
  /bin/cp /etc/security/audit_control.example /etc/security/audit_control
fi

/bin/launchctl enable system/com.apple.auditd
/bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.auditd.plist
/usr/sbin/audit -i
        fi
    else
        logmessage "Settings for: audit_auditd_enabled already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_auditd_enabled has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_control_acls_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_acls_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_acls_configure'))["exempt_reason"]
EOS
)

audit_control_acls_configure_audit_score=$($plb -c "print audit_control_acls_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_control_acls_configure_audit_score == "true" ]]; then
        ask 'audit_control_acls_configure - Run the command(s)-> /bin/chmod -N /etc/security/audit_control ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_control_acls_configure ..."
            /bin/chmod -N /etc/security/audit_control
        fi
    else
        logmessage "Settings for: audit_control_acls_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_control_acls_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_control_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_group_configure'))["exempt_reason"]
EOS
)

audit_control_group_configure_audit_score=$($plb -c "print audit_control_group_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_control_group_configure_audit_score == "true" ]]; then
        ask 'audit_control_group_configure - Run the command(s)-> /usr/bin/chgrp wheel /etc/security/audit_control ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_control_group_configure ..."
            /usr/bin/chgrp wheel /etc/security/audit_control
        fi
    else
        logmessage "Settings for: audit_control_group_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_control_group_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_control_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_mode_configure'))["exempt_reason"]
EOS
)

audit_control_mode_configure_audit_score=$($plb -c "print audit_control_mode_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_control_mode_configure_audit_score == "true" ]]; then
        ask 'audit_control_mode_configure - Run the command(s)-> /bin/chmod 440 /etc/security/audit_control ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_control_mode_configure ..."
            /bin/chmod 440 /etc/security/audit_control
        fi
    else
        logmessage "Settings for: audit_control_mode_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_control_mode_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_control_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_control_owner_configure'))["exempt_reason"]
EOS
)

audit_control_owner_configure_audit_score=$($plb -c "print audit_control_owner_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_control_owner_configure_audit_score == "true" ]]; then
        ask 'audit_control_owner_configure - Run the command(s)-> /usr/sbin/chown root /etc/security/audit_control ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_control_owner_configure ..."
            /usr/sbin/chown root /etc/security/audit_control
        fi
    else
        logmessage "Settings for: audit_control_owner_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_control_owner_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_files_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_group_configure'))["exempt_reason"]
EOS
)

audit_files_group_configure_audit_score=$($plb -c "print audit_files_group_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_files_group_configure_audit_score == "true" ]]; then
        ask 'audit_files_group_configure - Run the command(s)-> /usr/bin/chgrp -R wheel /var/audit/* ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_files_group_configure ..."
            /usr/bin/chgrp -R wheel /var/audit/*
        fi
    else
        logmessage "Settings for: audit_files_group_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_files_group_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_files_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_mode_configure'))["exempt_reason"]
EOS
)

audit_files_mode_configure_audit_score=$($plb -c "print audit_files_mode_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_files_mode_configure_audit_score == "true" ]]; then
        ask 'audit_files_mode_configure - Run the command(s)-> /bin/chmod 440 /var/audit/* ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_files_mode_configure ..."
            /bin/chmod 440 /var/audit/*
        fi
    else
        logmessage "Settings for: audit_files_mode_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_files_mode_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_files_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_files_owner_configure'))["exempt_reason"]
EOS
)

audit_files_owner_configure_audit_score=$($plb -c "print audit_files_owner_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_files_owner_configure_audit_score == "true" ]]; then
        ask 'audit_files_owner_configure - Run the command(s)-> /usr/sbin/chown -R root /var/audit/* ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_files_owner_configure ..."
            /usr/sbin/chown -R root /var/audit/*
        fi
    else
        logmessage "Settings for: audit_files_owner_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_files_owner_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_folder_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folder_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folder_group_configure'))["exempt_reason"]
EOS
)

audit_folder_group_configure_audit_score=$($plb -c "print audit_folder_group_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_folder_group_configure_audit_score == "true" ]]; then
        ask 'audit_folder_group_configure - Run the command(s)-> /usr/bin/chgrp wheel /var/audit ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_folder_group_configure ..."
            /usr/bin/chgrp wheel /var/audit
        fi
    else
        logmessage "Settings for: audit_folder_group_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_folder_group_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_folder_owner_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folder_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folder_owner_configure'))["exempt_reason"]
EOS
)

audit_folder_owner_configure_audit_score=$($plb -c "print audit_folder_owner_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_folder_owner_configure_audit_score == "true" ]]; then
        ask 'audit_folder_owner_configure - Run the command(s)-> /usr/sbin/chown root /var/audit ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_folder_owner_configure ..."
            /usr/sbin/chown root /var/audit
        fi
    else
        logmessage "Settings for: audit_folder_owner_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_folder_owner_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_folders_mode_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folders_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_folders_mode_configure'))["exempt_reason"]
EOS
)

audit_folders_mode_configure_audit_score=$($plb -c "print audit_folders_mode_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_folders_mode_configure_audit_score == "true" ]]; then
        ask 'audit_folders_mode_configure - Run the command(s)-> /bin/chmod 700 /var/audit ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_folders_mode_configure ..."
            /bin/chmod 700 /var/audit
        fi
    else
        logmessage "Settings for: audit_folders_mode_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_folders_mode_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_retention_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-11
# * AU-4

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_retention_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('audit_retention_configure'))["exempt_reason"]
EOS
)

audit_retention_configure_audit_score=$($plb -c "print audit_retention_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_retention_configure_audit_score == "true" ]]; then
        ask 'audit_retention_configure - Run the command(s)-> /usr/bin/sed -i.bak '"'"'s/^expire-after.*/expire-after:60d OR 5G/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_retention_configure ..."
            /usr/bin/sed -i.bak 's/^expire-after.*/expire-after:60d OR 5G/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_retention_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_retention_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_anti_virus_installed -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_anti_virus_installed'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_anti_virus_installed'))["exempt_reason"]
EOS
)

os_anti_virus_installed_audit_score=$($plb -c "print os_anti_virus_installed:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_anti_virus_installed_audit_score == "true" ]]; then
        ask 'os_anti_virus_installed - Run the command(s)-> /bin/launchctl load -w /Library/Apple/System/Library/LaunchDaemons/com.apple.XProtect.daemon.scan.plist
/bin/launchctl load -w /Library/Apple/System/Library/LaunchDaemons/com.apple.XprotectFramework.PluginService.plist ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_anti_virus_installed ..."
            /bin/launchctl load -w /Library/Apple/System/Library/LaunchDaemons/com.apple.XProtect.daemon.scan.plist
/bin/launchctl load -w /Library/Apple/System/Library/LaunchDaemons/com.apple.XprotectFramework.PluginService.plist
        fi
    else
        logmessage "Settings for: os_anti_virus_installed already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_anti_virus_installed has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_authenticated_root_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-3
# * CM-5
# * MA-4(1)
# * SC-34
# * SI-7, SI-7(6)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_authenticated_root_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_authenticated_root_enable'))["exempt_reason"]
EOS
)

os_authenticated_root_enable_audit_score=$($plb -c "print os_authenticated_root_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_authenticated_root_enable_audit_score == "true" ]]; then
        ask 'os_authenticated_root_enable - Run the command(s)-> /usr/bin/csrutil authenticated-root enable ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_authenticated_root_enable ..."
            /usr/bin/csrutil authenticated-root enable
        fi
    else
        logmessage "Settings for: os_authenticated_root_enable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_authenticated_root_enable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_gatekeeper_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-14
# * CM-5
# * SI-3
# * SI-7(1), SI-7(15)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_gatekeeper_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_gatekeeper_enable'))["exempt_reason"]
EOS
)

os_gatekeeper_enable_audit_score=$($plb -c "print os_gatekeeper_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_gatekeeper_enable_audit_score == "true" ]]; then
        ask 'os_gatekeeper_enable - Run the command(s)-> /usr/sbin/spctl --global-enable ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_gatekeeper_enable ..."
            /usr/sbin/spctl --global-enable
        fi
    else
        logmessage "Settings for: os_gatekeeper_enable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_gatekeeper_enable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_guest_folder_removed -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_guest_folder_removed'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_guest_folder_removed'))["exempt_reason"]
EOS
)

os_guest_folder_removed_audit_score=$($plb -c "print os_guest_folder_removed:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_guest_folder_removed_audit_score == "true" ]]; then
        ask 'os_guest_folder_removed - Run the command(s)-> /bin/rm -Rf /Users/Guest ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_guest_folder_removed ..."
            /bin/rm -Rf /Users/Guest
        fi
    else
        logmessage "Settings for: os_guest_folder_removed already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_guest_folder_removed has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_home_folders_secure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_home_folders_secure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_home_folders_secure'))["exempt_reason"]
EOS
)

os_home_folders_secure_audit_score=$($plb -c "print os_home_folders_secure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_home_folders_secure_audit_score == "true" ]]; then
        ask 'os_home_folders_secure - Run the command(s)-> IFS=$'"'"'\n'"'"'
for userDirs in $( /usr/bin/find /System/Volumes/Data/Users -mindepth 1 -maxdepth 1 -type d ! \( -perm 700 -o -perm 711 \) | /usr/bin/grep -v "Shared" | /usr/bin/grep -v "Guest" ); do
  /bin/chmod og-rwx "$userDirs"
done
unset IFS ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_home_folders_secure ..."
            IFS=$'\n'
for userDirs in $( /usr/bin/find /System/Volumes/Data/Users -mindepth 1 -maxdepth 1 -type d ! \( -perm 700 -o -perm 711 \) | /usr/bin/grep -v "Shared" | /usr/bin/grep -v "Guest" ); do
  /bin/chmod og-rwx "$userDirs"
done
unset IFS
        fi
    else
        logmessage "Settings for: os_home_folders_secure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_home_folders_secure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_httpd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_httpd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_httpd_disable'))["exempt_reason"]
EOS
)

os_httpd_disable_audit_score=$($plb -c "print os_httpd_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_httpd_disable_audit_score == "true" ]]; then
        ask 'os_httpd_disable - Run the command(s)-> /bin/launchctl disable system/org.apache.httpd ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_httpd_disable ..."
            /bin/launchctl disable system/org.apache.httpd
        fi
    else
        logmessage "Settings for: os_httpd_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_httpd_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_install_log_retention_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-11
# * AU-4

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_install_log_retention_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_install_log_retention_configure'))["exempt_reason"]
EOS
)

os_install_log_retention_configure_audit_score=$($plb -c "print os_install_log_retention_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_install_log_retention_configure_audit_score == "true" ]]; then
        ask 'os_install_log_retention_configure - Run the command(s)-> /usr/bin/sed -i '"'"''"'"' "s/\* file \/var\/log\/install.log.*/\* file \/var\/log\/install.log format='"'"'\$\(\(Time\)\(JZ\)\) \$Host \$\(Sender\)\[\$\(PID\\)\]: \$Message'"'"' rotate=utc compress file_max=50M size_only ttl=365/g" /etc/asl/com.apple.install ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_install_log_retention_configure ..."
            /usr/bin/sed -i '' "s/\* file \/var\/log\/install.log.*/\* file \/var\/log\/install.log format='\$\(\(Time\)\(JZ\)\) \$Host \$\(Sender\)\[\$\(PID\\)\]: \$Message' rotate=utc compress file_max=50M size_only ttl=365/g" /etc/asl/com.apple.install
        fi
    else
        logmessage "Settings for: os_install_log_retention_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_install_log_retention_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_mobile_file_integrity_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_mobile_file_integrity_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_mobile_file_integrity_enable'))["exempt_reason"]
EOS
)

os_mobile_file_integrity_enable_audit_score=$($plb -c "print os_mobile_file_integrity_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_mobile_file_integrity_enable_audit_score == "true" ]]; then
        ask 'os_mobile_file_integrity_enable - Run the command(s)-> /usr/sbin/nvram boot-args="" ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_mobile_file_integrity_enable ..."
            /usr/sbin/nvram boot-args=""
        fi
    else
        logmessage "Settings for: os_mobile_file_integrity_enable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_mobile_file_integrity_enable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_nfsd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_nfsd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_nfsd_disable'))["exempt_reason"]
EOS
)

os_nfsd_disable_audit_score=$($plb -c "print os_nfsd_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_nfsd_disable_audit_score == "true" ]]; then
        ask 'os_nfsd_disable - Run the command(s)-> /bin/launchctl disable system/com.apple.nfsd ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_nfsd_disable ..."
            /bin/launchctl disable system/com.apple.nfsd
        fi
    else
        logmessage "Settings for: os_nfsd_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_nfsd_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_password_hint_remove -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-6

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_password_hint_remove'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_password_hint_remove'))["exempt_reason"]
EOS
)

os_password_hint_remove_audit_score=$($plb -c "print os_password_hint_remove:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_password_hint_remove_audit_score == "true" ]]; then
        ask 'os_password_hint_remove - Run the command(s)-> for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '"'"'$2 > 500 {print $1}'"'"'); do
  /usr/bin/dscl . -delete /Users/$u hint
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_password_hint_remove ..."
            for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 > 500 {print $1}'); do
  /usr/bin/dscl . -delete /Users/$u hint
done
        fi
    else
        logmessage "Settings for: os_password_hint_remove already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_password_hint_remove has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_power_nap_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_power_nap_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_power_nap_disable'))["exempt_reason"]
EOS
)

os_power_nap_disable_audit_score=$($plb -c "print os_power_nap_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_power_nap_disable_audit_score == "true" ]]; then
        ask 'os_power_nap_disable - Run the command(s)-> /usr/bin/pmset -a powernap 0 ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_power_nap_disable ..."
            /usr/bin/pmset -a powernap 0
        fi
    else
        logmessage "Settings for: os_power_nap_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_power_nap_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_root_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_root_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_root_disable'))["exempt_reason"]
EOS
)

os_root_disable_audit_score=$($plb -c "print os_root_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_root_disable_audit_score == "true" ]]; then
        ask 'os_root_disable - Run the command(s)-> /usr/bin/dscl . -create /Users/root UserShell /usr/bin/false ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_root_disable ..."
            /usr/bin/dscl . -create /Users/root UserShell /usr/bin/false
        fi
    else
        logmessage "Settings for: os_root_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_root_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_show_filename_extensions_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_show_filename_extensions_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_show_filename_extensions_enable'))["exempt_reason"]
EOS
)

os_show_filename_extensions_enable_audit_score=$($plb -c "print os_show_filename_extensions_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_show_filename_extensions_enable_audit_score == "true" ]]; then
        ask 'os_show_filename_extensions_enable - Run the command(s)-> /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults write /Users/"$CURRENT_USER"/Library/Preferences/.GlobalPreferences AppleShowAllExtensions -bool true ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_show_filename_extensions_enable ..."
            /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults write /Users/"$CURRENT_USER"/Library/Preferences/.GlobalPreferences AppleShowAllExtensions -bool true
        fi
    else
        logmessage "Settings for: os_show_filename_extensions_enable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_show_filename_extensions_enable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sip_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-3
# * AU-9, AU-9(3)
# * CM-5, CM-5(6)
# * SC-4
# * SI-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sip_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sip_enable'))["exempt_reason"]
EOS
)

os_sip_enable_audit_score=$($plb -c "print os_sip_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sip_enable_audit_score == "true" ]]; then
        ask 'os_sip_enable - Run the command(s)-> /usr/bin/csrutil enable ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sip_enable ..."
            /usr/bin/csrutil enable
        fi
    else
        logmessage "Settings for: os_sip_enable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sip_enable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sudo_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sudo_timeout_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sudo_timeout_configure'))["exempt_reason"]
EOS
)

os_sudo_timeout_configure_audit_score=$($plb -c "print os_sudo_timeout_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sudo_timeout_configure_audit_score == "true" ]]; then
        ask 'os_sudo_timeout_configure - Run the command(s)-> /usr/bin/find /etc/sudoers* -type f -exec sed -i '"'"''"'"' '"'"'/timestamp_timeout/d'"'"' '"'"'{}'"'"' \;
/bin/echo "Defaults timestamp_timeout=0" >> /etc/sudoers.d/mscp ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sudo_timeout_configure ..."
            /usr/bin/find /etc/sudoers* -type f -exec sed -i '' '/timestamp_timeout/d' '{}' \;
/bin/echo "Defaults timestamp_timeout=0" >> /etc/sudoers.d/mscp
        fi
    else
        logmessage "Settings for: os_sudo_timeout_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sudo_timeout_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sudoers_timestamp_type_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-5(1)
# * IA-11

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt_reason"]
EOS
)

os_sudoers_timestamp_type_configure_audit_score=$($plb -c "print os_sudoers_timestamp_type_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sudoers_timestamp_type_configure_audit_score == "true" ]]; then
        ask 'os_sudoers_timestamp_type_configure - Run the command(s)-> /usr/bin/find /etc/sudoers* -type f -exec sed -i '"'"''"'"' '"'"'/timestamp_type/d; /!tty_tickets/d'"'"' '"'"'{}'"'"' \; ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sudoers_timestamp_type_configure ..."
            /usr/bin/find /etc/sudoers* -type f -exec sed -i '' '/timestamp_type/d; /!tty_tickets/d' '{}' \;
        fi
    else
        logmessage "Settings for: os_sudoers_timestamp_type_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sudoers_timestamp_type_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_system_wide_applications_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_system_wide_applications_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_system_wide_applications_configure'))["exempt_reason"]
EOS
)

os_system_wide_applications_configure_audit_score=$($plb -c "print os_system_wide_applications_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_system_wide_applications_configure_audit_score == "true" ]]; then
        ask 'os_system_wide_applications_configure - Run the command(s)-> IFS=$'"'"'\n'"'"'
for apps in $( /usr/bin/find /Applications -iname "*\.app" -type d -perm -2 ); do
  /bin/chmod -R o-w "$apps"
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_system_wide_applications_configure ..."
            IFS=$'\n'
for apps in $( /usr/bin/find /Applications -iname "*\.app" -type d -perm -2 ); do
  /bin/chmod -R o-w "$apps"
done
        fi
    else
        logmessage "Settings for: os_system_wide_applications_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_system_wide_applications_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_time_server_enabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12(1)
# * SC-45(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_time_server_enabled'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_time_server_enabled'))["exempt_reason"]
EOS
)

os_time_server_enabled_audit_score=$($plb -c "print os_time_server_enabled:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_time_server_enabled_audit_score == "true" ]]; then
        ask 'os_time_server_enabled - Run the command(s)-> /bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.timed.plist ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_time_server_enabled ..."
            /bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.timed.plist
        fi
    else
        logmessage "Settings for: os_time_server_enabled already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_time_server_enabled has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_unlock_active_user_session_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt_reason"]
EOS
)

os_unlock_active_user_session_disable_audit_score=$($plb -c "print os_unlock_active_user_session_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_unlock_active_user_session_disable_audit_score == "true" ]]; then
        ask 'os_unlock_active_user_session_disable - Run the command(s)-> /usr/bin/security authorizationdb write system.login.screensaver "authenticate-session-owner" ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_unlock_active_user_session_disable ..."
            /usr/bin/security authorizationdb write system.login.screensaver "authenticate-session-owner"
        fi
    else
        logmessage "Settings for: os_unlock_active_user_session_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_unlock_active_user_session_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_world_writable_system_folder_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_world_writable_system_folder_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('os_world_writable_system_folder_configure'))["exempt_reason"]
EOS
)

os_world_writable_system_folder_configure_audit_score=$($plb -c "print os_world_writable_system_folder_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_world_writable_system_folder_configure_audit_score == "true" ]]; then
        ask 'os_world_writable_system_folder_configure - Run the command(s)-> IFS=$'"'"'\n'"'"'
for sysPermissions in $( /usr/bin/find /System/Volumes/Data/System -type d -perm -2 | /usr/bin/grep -vE "downloadDir|locks" ); do
  /bin/chmod -R o-w "$sysPermissions"
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_world_writable_system_folder_configure ..."
            IFS=$'\n'
for sysPermissions in $( /usr/bin/find /System/Volumes/Data/System -type d -perm -2 | /usr/bin/grep -vE "downloadDir|locks" ); do
  /bin/chmod -R o-w "$sysPermissions"
done
        fi
    else
        logmessage "Settings for: os_world_writable_system_folder_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_world_writable_system_folder_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_bluetooth_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-18(4)
# * AC-3
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt_reason"]
EOS
)

system_settings_bluetooth_sharing_disable_audit_score=$($plb -c "print system_settings_bluetooth_sharing_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_bluetooth_sharing_disable_audit_score == "true" ]]; then
        ask 'system_settings_bluetooth_sharing_disable - Run the command(s)-> /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_bluetooth_sharing_disable ..."
            /usr/bin/sudo -u "$CURRENT_USER" /usr/bin/defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false
        fi
    else
        logmessage "Settings for: system_settings_bluetooth_sharing_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_bluetooth_sharing_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_cd_dvd_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_cd_dvd_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_cd_dvd_sharing_disable'))["exempt_reason"]
EOS
)

system_settings_cd_dvd_sharing_disable_audit_score=$($plb -c "print system_settings_cd_dvd_sharing_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_cd_dvd_sharing_disable_audit_score == "true" ]]; then
        ask 'system_settings_cd_dvd_sharing_disable - Run the command(s)-> /bin/launchctl unload /System/Library/LaunchDaemons/com.apple.ODSAgent.plist ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_cd_dvd_sharing_disable ..."
            /bin/launchctl unload /System/Library/LaunchDaemons/com.apple.ODSAgent.plist
        fi
    else
        logmessage "Settings for: system_settings_cd_dvd_sharing_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_cd_dvd_sharing_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_firewall_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-4
# * CM-7, CM-7(1)
# * SC-7, SC-7(12)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_firewall_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_firewall_enable'))["exempt_reason"]
EOS
)

system_settings_firewall_enable_audit_score=$($plb -c "print system_settings_firewall_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_firewall_enable_audit_score == "true" ]]; then
        ask 'system_settings_firewall_enable - Run the command(s)-> /usr/bin/defaults write /Library/Preferences/com.apple.alf globalstate -int 1 ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_firewall_enable ..."
            /usr/bin/defaults write /Library/Preferences/com.apple.alf globalstate -int 1
        fi
    else
        logmessage "Settings for: system_settings_firewall_enable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_firewall_enable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_firewall_stealth_mode_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
# * SC-7, SC-7(16)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_firewall_stealth_mode_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_firewall_stealth_mode_enable'))["exempt_reason"]
EOS
)

system_settings_firewall_stealth_mode_enable_audit_score=$($plb -c "print system_settings_firewall_stealth_mode_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_firewall_stealth_mode_enable_audit_score == "true" ]]; then
        ask 'system_settings_firewall_stealth_mode_enable - Run the command(s)-> /usr/bin/defaults write /Library/Preferences/com.apple.alf stealthenabled -int 1 ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_firewall_stealth_mode_enable ..."
            /usr/bin/defaults write /Library/Preferences/com.apple.alf stealthenabled -int 1
        fi
    else
        logmessage "Settings for: system_settings_firewall_stealth_mode_enable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_firewall_stealth_mode_enable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_guest_access_smb_disable -----#####
## Addresses the following NIST 800-53 controls: N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_guest_access_smb_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_guest_access_smb_disable'))["exempt_reason"]
EOS
)

system_settings_guest_access_smb_disable_audit_score=$($plb -c "print system_settings_guest_access_smb_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_guest_access_smb_disable_audit_score == "true" ]]; then
        ask 'system_settings_guest_access_smb_disable - Run the command(s)-> /usr/sbin/sysadminctl -smbGuestAccess off ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_guest_access_smb_disable ..."
            /usr/sbin/sysadminctl -smbGuestAccess off
        fi
    else
        logmessage "Settings for: system_settings_guest_access_smb_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_guest_access_smb_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_printer_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_printer_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_printer_sharing_disable'))["exempt_reason"]
EOS
)

system_settings_printer_sharing_disable_audit_score=$($plb -c "print system_settings_printer_sharing_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_printer_sharing_disable_audit_score == "true" ]]; then
        ask 'system_settings_printer_sharing_disable - Run the command(s)-> /usr/sbin/cupsctl --no-share-printers
/usr/bin/lpstat -p | awk '"'"'{print $2}'"'"'| /usr/bin/xargs -I{} lpadmin -p {} -o printer-is-shared=false ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_printer_sharing_disable ..."
            /usr/sbin/cupsctl --no-share-printers
/usr/bin/lpstat -p | awk '{print $2}'| /usr/bin/xargs -I{} lpadmin -p {} -o printer-is-shared=false
        fi
    else
        logmessage "Settings for: system_settings_printer_sharing_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_printer_sharing_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_rae_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_rae_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_rae_disable'))["exempt_reason"]
EOS
)

system_settings_rae_disable_audit_score=$($plb -c "print system_settings_rae_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_rae_disable_audit_score == "true" ]]; then
        ask 'system_settings_rae_disable - Run the command(s)-> /usr/sbin/systemsetup -setremoteappleevents off
/bin/launchctl disable system/com.apple.AEServer ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_rae_disable ..."
            /usr/sbin/systemsetup -setremoteappleevents off
/bin/launchctl disable system/com.apple.AEServer
        fi
    else
        logmessage "Settings for: system_settings_rae_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_rae_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_remote_management_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_remote_management_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_remote_management_disable'))["exempt_reason"]
EOS
)

system_settings_remote_management_disable_audit_score=$($plb -c "print system_settings_remote_management_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_remote_management_disable_audit_score == "true" ]]; then
        ask 'system_settings_remote_management_disable - Run the command(s)-> /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_remote_management_disable ..."
            /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop
        fi
    else
        logmessage "Settings for: system_settings_remote_management_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_remote_management_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_screen_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt_reason"]
EOS
)

system_settings_screen_sharing_disable_audit_score=$($plb -c "print system_settings_screen_sharing_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_screen_sharing_disable_audit_score == "true" ]]; then
        ask 'system_settings_screen_sharing_disable - Run the command(s)-> /bin/launchctl disable system/com.apple.screensharing ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_screen_sharing_disable ..."
            /bin/launchctl disable system/com.apple.screensharing
        fi
    else
        logmessage "Settings for: system_settings_screen_sharing_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_screen_sharing_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_smbd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_smbd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_smbd_disable'))["exempt_reason"]
EOS
)

system_settings_smbd_disable_audit_score=$($plb -c "print system_settings_smbd_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_smbd_disable_audit_score == "true" ]]; then
        ask 'system_settings_smbd_disable - Run the command(s)-> /bin/launchctl disable system/com.apple.smbd ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_smbd_disable ..."
            /bin/launchctl disable system/com.apple.smbd
        fi
    else
        logmessage "Settings for: system_settings_smbd_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_smbd_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_softwareupdate_current -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_softwareupdate_current'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_softwareupdate_current'))["exempt_reason"]
EOS
)

system_settings_softwareupdate_current_audit_score=$($plb -c "print system_settings_softwareupdate_current:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_softwareupdate_current_audit_score == "true" ]]; then
        ask 'system_settings_softwareupdate_current - Run the command(s)-> /usr/sbin/softwareupdate -i -a ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_softwareupdate_current ..."
            /usr/sbin/softwareupdate -i -a
        fi
    else
        logmessage "Settings for: system_settings_softwareupdate_current already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_softwareupdate_current has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_ssh_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_ssh_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_ssh_disable'))["exempt_reason"]
EOS
)

system_settings_ssh_disable_audit_score=$($plb -c "print system_settings_ssh_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_ssh_disable_audit_score == "true" ]]; then
        ask 'system_settings_ssh_disable - Run the command(s)-> /usr/sbin/systemsetup -f -setremotelogin off >/dev/null
/bin/launchctl disable system/com.openssh.sshd ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_ssh_disable ..."
            /usr/sbin/systemsetup -f -setremotelogin off >/dev/null
/bin/launchctl disable system/com.openssh.sshd
        fi
    else
        logmessage "Settings for: system_settings_ssh_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_ssh_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_system_wide_preferences_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6, AC-6(1), AC-6(2)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt_reason"]
EOS
)

system_settings_system_wide_preferences_configure_audit_score=$($plb -c "print system_settings_system_wide_preferences_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_system_wide_preferences_configure_audit_score == "true" ]]; then
        ask 'system_settings_system_wide_preferences_configure - Run the command(s)-> authDBs=("system.preferences" "system.preferences.energysaver" "system.preferences.network" "system.preferences.printing" "system.preferences.sharing" "system.preferences.softwareupdate" "system.preferences.startupdisk" "system.preferences.timemachine")

for section in ${authDBs[@]}; do
  /usr/bin/security -q authorizationdb read "$section" > "/tmp/$section.plist"

  class_key_value=$(/usr/libexec/PlistBuddy -c "Print :class" "/tmp/$section.plist" 2>&1)
  if [[ "$class_key_value" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :class string user" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :class user" "/tmp/$section.plist"
  fi

  key_value=$(/usr/libexec/PlistBuddy -c "Print :shared" "/tmp/$section.plist" 2>&1)  	
  if [[ "$key_value" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :shared bool false" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :shared false" "/tmp/$section.plist"
  fi

  auth_user_key=$(/usr/libexec/PlistBuddy -c "Print :authenticate-user" "/tmp/$section.plist" 2>&1)  	
  if [[ "$auth_user_key" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :authenticate-user bool true" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :authenticate-user true" "/tmp/$section.plist"
  fi

  session_owner_key=$(/usr/libexec/PlistBuddy -c "Print :session-owner" "/tmp/$section.plist" 2>&1)  	
  if [[ "$session_owner_key" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :session-owner bool false" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :session-owner false" "/tmp/$section.plist"
  fi

  group_key=$(/usr/libexec/PlistBuddy -c "Print :group" "/tmp/$section.plist" 2>&1)
  if [[ "$group_key" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :group string admin" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :group admin" "/tmp/$section.plist"
  fi

  /usr/bin/security -q authorizationdb write "$section" < "/tmp/$section.plist"
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_system_wide_preferences_configure ..."
            authDBs=("system.preferences" "system.preferences.energysaver" "system.preferences.network" "system.preferences.printing" "system.preferences.sharing" "system.preferences.softwareupdate" "system.preferences.startupdisk" "system.preferences.timemachine")

for section in ${authDBs[@]}; do
  /usr/bin/security -q authorizationdb read "$section" > "/tmp/$section.plist"

  class_key_value=$(/usr/libexec/PlistBuddy -c "Print :class" "/tmp/$section.plist" 2>&1)
  if [[ "$class_key_value" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :class string user" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :class user" "/tmp/$section.plist"
  fi

  key_value=$(/usr/libexec/PlistBuddy -c "Print :shared" "/tmp/$section.plist" 2>&1)  	
  if [[ "$key_value" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :shared bool false" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :shared false" "/tmp/$section.plist"
  fi

  auth_user_key=$(/usr/libexec/PlistBuddy -c "Print :authenticate-user" "/tmp/$section.plist" 2>&1)  	
  if [[ "$auth_user_key" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :authenticate-user bool true" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :authenticate-user true" "/tmp/$section.plist"
  fi

  session_owner_key=$(/usr/libexec/PlistBuddy -c "Print :session-owner" "/tmp/$section.plist" 2>&1)  	
  if [[ "$session_owner_key" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :session-owner bool false" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :session-owner false" "/tmp/$section.plist"
  fi

  group_key=$(/usr/libexec/PlistBuddy -c "Print :group" "/tmp/$section.plist" 2>&1)
  if [[ "$group_key" == *"Does Not Exist"* ]]; then
    /usr/libexec/PlistBuddy -c "Add :group string admin" "/tmp/$section.plist"
  else
    /usr/libexec/PlistBuddy -c "Set :group admin" "/tmp/$section.plist"
  fi

  /usr/bin/security -q authorizationdb write "$section" < "/tmp/$section.plist"
done
        fi
    else
        logmessage "Settings for: system_settings_system_wide_preferences_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_system_wide_preferences_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_wake_network_access_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_wake_network_access_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cis_lvl1.audit').objectForKey('system_settings_wake_network_access_disable'))["exempt_reason"]
EOS
)

system_settings_wake_network_access_disable_audit_score=$($plb -c "print system_settings_wake_network_access_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_wake_network_access_disable_audit_score == "true" ]]; then
        ask 'system_settings_wake_network_access_disable - Run the command(s)-> /usr/bin/pmset -a womp 0 ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_wake_network_access_disable ..."
            /usr/bin/pmset -a womp 0
        fi
    else
        logmessage "Settings for: system_settings_wake_network_access_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_wake_network_access_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
echo "$(date -u) Remediation complete" >> "$audit_log"

} 2>/dev/null

usage=(
    "$0 Usage"
    "$0 [--check] [--fix] [--cfc] [--stats] [--compliant] [--non_compliant] [--reset] [--reset-all] [--quiet=<value>]"
    " "
    "Optional parameters:"
    "--check            :   run the compliance checks without interaction"
    "--fix              :   run the remediation commands without interaction"
    "--cfc              :   runs a check, fix, check without interaction"
    "--stats            :   display the statistics from last compliance check"
    "--compliant        :   reports the number of compliant checks"
    "--non_compliant    :   reports the number of non_compliant checks"
    "--reset            :   clear out all results for current baseline"
    "--reset-all        :   clear out all results for ALL MSCP baselines"
    "--quiet=<value>    :   1 - show only failed and exempted checks in output"
    "                       2 - show minimal output"
  )

zparseopts -D -E -help=flag_help -check=check -fix=fix -stats=stats -compliant=compliant_opt -non_compliant=non_compliant_opt -reset=reset -reset-all=reset_all -cfc=cfc -quiet:=quiet || { print -l $usage && return }

[[ -z "$flag_help" ]] || { print -l $usage && return }

if [[ ! -z $quiet ]];then
  [[ ! -z ${quiet[2][2]} ]] || { print -l $usage && return }
fi

if [[ $reset ]] || [[ $reset_all ]]; then reset_plist; fi

if [[ $check ]] || [[ $fix ]] || [[ $cfc ]] || [[ $stats ]] || [[ $compliant_opt ]] || [[ $non_compliant_opt ]]; then
    if [[ $fix ]]; then run_fix; fi
    if [[ $check ]]; then run_scan; fi
    if [[ $cfc ]]; then run_scan; run_fix; run_scan; fi
    if [[ $stats ]];then generate_stats; fi
    if [[ $compliant_opt ]];then compliance_count "compliant"; fi
    if [[ $non_compliant_opt ]];then compliance_count "non-compliant"; fi
else
    while true; do
        show_menus
        read_options
    done
fi

if [[ "$ssh_key_check" -ne 0 ]]; then
    /bin/rm /etc/ssh/ssh_host_rsa_key
    /bin/rm /etc/ssh/ssh_host_rsa_key.pub
    ssh_key_check=0
fi
    