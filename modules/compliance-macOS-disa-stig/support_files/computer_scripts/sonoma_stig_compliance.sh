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

audit_plist="/Library/Preferences/org.stig.audit.plist"
audit_log="/Library/Logs/stig_baseline.log"

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
    lastComplianceScan=$(defaults read /Library/Preferences/org.stig.audit.plist lastComplianceCheck)

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
        echo "Clearing results from /Library/Preferences/org.stig.audit.plist"
        rm -f /Library/Preferences/org.stig.audit.plist
        rm -f /Library/Logs/stig_baseline.log
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey("$rule"))["exempt"]
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
 	echo "$(date -u) Beginning stig baseline scan" >> "$audit_log"
else
 	echo "$(date -u) Beginning stig baseline scan" > "$audit_log"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_acls_files_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_acls_files_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_acls_files_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_acls_files_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_acls_files_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_acls_files_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_acls_files_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_acls_files_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_acls_files_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_acls_files_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_acls_folders_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_acls_folders_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_acls_folders_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_acls_folders_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_acls_folders_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_acls_folders_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_acls_folders_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_acls_folders_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_acls_folders_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_acls_folders_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_auditd_enabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_auditd_enabled'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_auditd_enabled passed (Result: $result_value, Expected: "{'string': 'pass'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_auditd_enabled failed (Result: $result_value, Expected: \"{'string': 'pass'}\")"
            /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_auditd_enabled" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_auditd_enabled failed (Result: $result_value, Expected: "{'string': 'pass'}")"
        else
            logmessage "audit_auditd_enabled failed (Result: $result_value, Expected: \"{'string': 'pass'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_auditd_enabled" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_auditd_enabled failed (Result: $result_value, Expected: "{'string': 'pass'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_auditd_enabled does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_auditd_enabled -dict-add finding -bool NO
fi

#####----- Rule: audit_configure_capacity_notify -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F: '/^minfree/{print $2}' /etc/security/audit_control
)
    # expected result {'integer': 25}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_configure_capacity_notify'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_configure_capacity_notify'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_configure_capacity_notify" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "25" ]]; then
        logmessage "audit_configure_capacity_notify passed (Result: $result_value, Expected: \"{'integer': 25}\")"
        /usr/bin/defaults write "$audit_plist" audit_configure_capacity_notify -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_configure_capacity_notify" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_configure_capacity_notify -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_configure_capacity_notify passed (Result: $result_value, Expected: "{'integer': 25}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_configure_capacity_notify failed (Result: $result_value, Expected: \"{'integer': 25}\")"
            /usr/bin/defaults write "$audit_plist" audit_configure_capacity_notify -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_configure_capacity_notify" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_configure_capacity_notify -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_configure_capacity_notify failed (Result: $result_value, Expected: "{'integer': 25}")"
        else
            logmessage "audit_configure_capacity_notify failed (Result: $result_value, Expected: \"{'integer': 25}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_configure_capacity_notify -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_configure_capacity_notify" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_configure_capacity_notify -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_configure_capacity_notify failed (Result: $result_value, Expected: "{'integer': 25}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_configure_capacity_notify does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_configure_capacity_notify -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_acls_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_acls_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_control_acls_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_control_acls_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_acls_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_control_acls_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_control_acls_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_acls_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_control_acls_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_control_acls_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_group_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_control_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_control_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_group_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_control_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_control_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_group_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_control_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_control_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_mode_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_control_mode_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_control_mode_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_mode_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_control_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_control_mode_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_mode_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_control_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_control_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_owner_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_control_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_control_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_owner_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_control_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_control_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_control_owner_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_control_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_control_owner_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_control_owner_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_failure_halt -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-5
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^policy/ {print $NF}' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec 'ahlt'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_failure_halt'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_failure_halt'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_failure_halt" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_failure_halt passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_failure_halt -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_failure_halt" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_failure_halt -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_failure_halt passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_failure_halt failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_failure_halt -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_failure_halt" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_failure_halt -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_failure_halt failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_failure_halt failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_failure_halt -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_failure_halt" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_failure_halt -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_failure_halt failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_failure_halt does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_failure_halt -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_group_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_files_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_files_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_group_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_files_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_files_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_group_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_files_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_files_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_mode_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_files_mode_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_files_mode_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_mode_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_files_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_files_mode_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_mode_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_files_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_files_mode_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_owner_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_files_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_files_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_owner_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_files_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_files_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_files_owner_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_files_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_files_owner_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_files_owner_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_flags_aa_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec 'aa'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_aa_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_aa_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_flags_aa_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_flags_aa_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_flags_aa_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_flags_aa_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_flags_aa_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_aa_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_aa_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_flags_aa_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_aa_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_aa_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_flags_aa_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_flags_aa_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_flags_ad_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12), AC-2(4)
# * AC-6(9)
# * AU-12
# * AU-2
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec 'ad'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_ad_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_ad_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_flags_ad_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_flags_ad_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_flags_ad_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_flags_ad_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_flags_ad_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_ad_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_ad_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_flags_ad_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_ad_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_ad_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_flags_ad_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_flags_ad_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_flags_ex_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * CM-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec '\-ex'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_ex_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_ex_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_flags_ex_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_flags_ex_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_flags_ex_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_flags_ex_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_flags_ex_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_ex_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_ex_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_flags_ex_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_ex_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_ex_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_flags_ex_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_flags_ex_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_flags_fd_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec '\-fd'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fd_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fd_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_flags_fd_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_flags_fd_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_flags_fd_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_flags_fd_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_flags_fd_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_flags_fd_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_flags_fd_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_fd_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_fd_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_flags_fd_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_fd_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_flags_fd_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_fd_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_fd_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_flags_fd_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_fd_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_flags_fd_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_flags_fd_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_flags_fm_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec '^fm'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fm_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fm_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_flags_fm_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_flags_fm_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_flags_fm_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_flags_fm_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_flags_fm_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_flags_fm_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_flags_fm_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_fm_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_fm_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_flags_fm_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_fm_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_flags_fm_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_fm_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_fm_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_flags_fm_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_fm_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_flags_fm_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_flags_fm_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_flags_fr_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec '\-fr'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fr_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fr_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_flags_fr_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_flags_fr_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_flags_fr_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_flags_fr_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_flags_fr_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_fr_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_fr_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_flags_fr_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_fr_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_fr_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_flags_fr_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_flags_fr_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_flags_fw_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec '\-fw'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fw_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fw_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_flags_fw_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_flags_fw_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_flags_fw_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_flags_fw_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_flags_fw_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_fw_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_fw_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_flags_fw_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_fw_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_fw_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_flags_fw_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_flags_fw_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_flags_lo_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17(1)
# * AC-2(12)
# * AU-12
# * AU-2
# * MA-4(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/awk -F':' '/^flags/ { print $NF }' /etc/security/audit_control | /usr/bin/tr ',' '\n' | /usr/bin/grep -Ec '^lo'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_lo_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_lo_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_flags_lo_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_flags_lo_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_flags_lo_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_flags_lo_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_flags_lo_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_lo_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_lo_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_flags_lo_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_flags_lo_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_flags_lo_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_flags_lo_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_flags_lo_configure -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folder_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folder_group_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_folder_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_folder_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folder_group_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_folder_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_folder_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folder_group_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_folder_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_folder_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folder_owner_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folder_owner_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_folder_owner_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_folder_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folder_owner_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_folder_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "audit_folder_owner_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folder_owner_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_folder_owner_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_folder_owner_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folders_mode_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folders_mode_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - audit_folders_mode_configure passed (Result: $result_value, Expected: "{'integer': 700}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_folders_mode_configure failed (Result: $result_value, Expected: \"{'integer': 700}\")"
            /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folders_mode_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_folders_mode_configure failed (Result: $result_value, Expected: "{'integer': 700}")"
        else
            logmessage "audit_folders_mode_configure failed (Result: $result_value, Expected: \"{'integer': 700}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_folders_mode_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_folders_mode_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_folders_mode_configure failed (Result: $result_value, Expected: "{'integer': 700}") - Exemption Allowed (Reason: "$exempt_reason")"
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
    # expected result {'string': '7d'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_retention_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_retention_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_retention_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "7d" ]]; then
        logmessage "audit_retention_configure passed (Result: $result_value, Expected: \"{'string': '7d'}\")"
        /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_retention_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_retention_configure passed (Result: $result_value, Expected: "{'string': '7d'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_retention_configure failed (Result: $result_value, Expected: \"{'string': '7d'}\")"
            /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_retention_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_retention_configure failed (Result: $result_value, Expected: "{'string': '7d'}")"
        else
            logmessage "audit_retention_configure failed (Result: $result_value, Expected: \"{'string': '7d'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_retention_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_retention_configure failed (Result: $result_value, Expected: "{'string': '7d'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_retention_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_retention_configure -dict-add finding -bool NO
fi

#####----- Rule: audit_settings_failure_notify -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-5, AU-5(2)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/grep -c "logger -s -p" /etc/security/audit_warn
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_settings_failure_notify'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_settings_failure_notify'))["exempt_reason"]
EOS
)   
    customref="$(echo "audit_settings_failure_notify" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "audit_settings_failure_notify passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" audit_settings_failure_notify -dict-add finding -bool NO
        if [[ ! "$customref" == "audit_settings_failure_notify" ]]; then
            /usr/bin/defaults write "$audit_plist" audit_settings_failure_notify -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - audit_settings_failure_notify passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "audit_settings_failure_notify failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" audit_settings_failure_notify -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_settings_failure_notify" ]]; then
                /usr/bin/defaults write "$audit_plist" audit_settings_failure_notify -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_settings_failure_notify failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "audit_settings_failure_notify failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" audit_settings_failure_notify -dict-add finding -bool YES
            if [[ ! "$customref" == "audit_settings_failure_notify" ]]; then
              /usr/bin/defaults write "$audit_plist" audit_settings_failure_notify -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - audit_settings_failure_notify failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "audit_settings_failure_notify does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" audit_settings_failure_notify -dict-add finding -bool NO
fi

#####----- Rule: auth_pam_login_smartcard_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(1), IA-2(2), IA-2(8)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/grep -Ec '^(auth\s+sufficient\s+pam_smartcard.so|auth\s+required\s+pam_deny.so)' /etc/pam.d/login
)
    # expected result {'integer': 2}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_login_smartcard_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_login_smartcard_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "auth_pam_login_smartcard_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "2" ]]; then
        logmessage "auth_pam_login_smartcard_enforce passed (Result: $result_value, Expected: \"{'integer': 2}\")"
        /usr/bin/defaults write "$audit_plist" auth_pam_login_smartcard_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "auth_pam_login_smartcard_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" auth_pam_login_smartcard_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - auth_pam_login_smartcard_enforce passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_pam_login_smartcard_enforce failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" auth_pam_login_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_pam_login_smartcard_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_pam_login_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_pam_login_smartcard_enforce failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "auth_pam_login_smartcard_enforce failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_pam_login_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_pam_login_smartcard_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_pam_login_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_pam_login_smartcard_enforce failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "auth_pam_login_smartcard_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" auth_pam_login_smartcard_enforce -dict-add finding -bool NO
fi

#####----- Rule: auth_pam_su_smartcard_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(1), IA-2(2), IA-2(8)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/grep -Ec '^(auth\s+sufficient\s+pam_smartcard.so|auth\s+required\s+pam_rootok.so)' /etc/pam.d/su
)
    # expected result {'integer': 2}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_su_smartcard_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_su_smartcard_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "auth_pam_su_smartcard_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "2" ]]; then
        logmessage "auth_pam_su_smartcard_enforce passed (Result: $result_value, Expected: \"{'integer': 2}\")"
        /usr/bin/defaults write "$audit_plist" auth_pam_su_smartcard_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "auth_pam_su_smartcard_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" auth_pam_su_smartcard_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - auth_pam_su_smartcard_enforce passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_pam_su_smartcard_enforce failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" auth_pam_su_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_pam_su_smartcard_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_pam_su_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_pam_su_smartcard_enforce failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "auth_pam_su_smartcard_enforce failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_pam_su_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_pam_su_smartcard_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_pam_su_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_pam_su_smartcard_enforce failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "auth_pam_su_smartcard_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" auth_pam_su_smartcard_enforce -dict-add finding -bool NO
fi

#####----- Rule: auth_pam_sudo_smartcard_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(1), IA-2(2), IA-2(8)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/grep -Ec '^(auth\s+sufficient\s+pam_smartcard.so|auth\s+required\s+pam_deny.so)' /etc/pam.d/sudo
)
    # expected result {'integer': 2}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_sudo_smartcard_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_sudo_smartcard_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "auth_pam_sudo_smartcard_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "2" ]]; then
        logmessage "auth_pam_sudo_smartcard_enforce passed (Result: $result_value, Expected: \"{'integer': 2}\")"
        /usr/bin/defaults write "$audit_plist" auth_pam_sudo_smartcard_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "auth_pam_sudo_smartcard_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" auth_pam_sudo_smartcard_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - auth_pam_sudo_smartcard_enforce passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_pam_sudo_smartcard_enforce failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" auth_pam_sudo_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_pam_sudo_smartcard_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_pam_sudo_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_pam_sudo_smartcard_enforce failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "auth_pam_sudo_smartcard_enforce failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_pam_sudo_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_pam_sudo_smartcard_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_pam_sudo_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_pam_sudo_smartcard_enforce failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "auth_pam_sudo_smartcard_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" auth_pam_sudo_smartcard_enforce -dict-add finding -bool NO
fi

#####----- Rule: auth_smartcard_allow -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(1), IA-2(12), IA-2(2)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.smartcard')\
.objectForKey('allowSmartCard').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_smartcard_allow'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_smartcard_allow'))["exempt_reason"]
EOS
)   
    customref="$(echo "auth_smartcard_allow" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "auth_smartcard_allow passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add finding -bool NO
        if [[ ! "$customref" == "auth_smartcard_allow" ]]; then
            /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - auth_smartcard_allow passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_smartcard_allow failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_allow" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_smartcard_allow failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "auth_smartcard_allow failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_allow" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_smartcard_allow failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "auth_smartcard_allow does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add finding -bool NO
fi

#####----- Rule: auth_smartcard_certificate_trust_enforce_moderate -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5(2)
# * SC-17
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.smartcard')\
.objectForKey('checkCertificateTrust').js
EOS
)
    # expected result {'integer': 2}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_smartcard_certificate_trust_enforce_moderate'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_smartcard_certificate_trust_enforce_moderate'))["exempt_reason"]
EOS
)   
    customref="$(echo "auth_smartcard_certificate_trust_enforce_moderate" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "2" ]]; then
        logmessage "auth_smartcard_certificate_trust_enforce_moderate passed (Result: $result_value, Expected: \"{'integer': 2}\")"
        /usr/bin/defaults write "$audit_plist" auth_smartcard_certificate_trust_enforce_moderate -dict-add finding -bool NO
        if [[ ! "$customref" == "auth_smartcard_certificate_trust_enforce_moderate" ]]; then
            /usr/bin/defaults write "$audit_plist" auth_smartcard_certificate_trust_enforce_moderate -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - auth_smartcard_certificate_trust_enforce_moderate passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_smartcard_certificate_trust_enforce_moderate failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_certificate_trust_enforce_moderate -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_certificate_trust_enforce_moderate" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_smartcard_certificate_trust_enforce_moderate -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_smartcard_certificate_trust_enforce_moderate failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "auth_smartcard_certificate_trust_enforce_moderate failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_certificate_trust_enforce_moderate -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_certificate_trust_enforce_moderate" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_smartcard_certificate_trust_enforce_moderate -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_smartcard_certificate_trust_enforce_moderate failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "auth_smartcard_certificate_trust_enforce_moderate does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" auth_smartcard_certificate_trust_enforce_moderate -dict-add finding -bool NO
fi

#####----- Rule: auth_smartcard_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(1), IA-2(12), IA-2(2), IA-2(6), IA-2(8)
# * IA-5(2)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.smartcard')\
.objectForKey('enforceSmartCard').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_smartcard_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_smartcard_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "auth_smartcard_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "auth_smartcard_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "auth_smartcard_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - auth_smartcard_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_smartcard_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_smartcard_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "auth_smartcard_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_smartcard_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "auth_smartcard_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add finding -bool NO
fi

#####----- Rule: auth_ssh_password_authentication_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(1), IA-2(2), IA-2(6), IA-2(8)
# * IA-5(2)
# * MA-4
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/sshd -G | /usr/bin/grep -Ec '^(passwordauthentication\s+no|kbdinteractiveauthentication\s+no)'
)
    # expected result {'integer': 2}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_ssh_password_authentication_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_ssh_password_authentication_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "auth_ssh_password_authentication_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "2" ]]; then
        logmessage "auth_ssh_password_authentication_disable passed (Result: $result_value, Expected: \"{'integer': 2}\")"
        /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "auth_ssh_password_authentication_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - auth_ssh_password_authentication_disable passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_ssh_password_authentication_disable failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_ssh_password_authentication_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_ssh_password_authentication_disable failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "auth_ssh_password_authentication_disable failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_ssh_password_authentication_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - auth_ssh_password_authentication_disable failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "auth_ssh_password_authentication_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_addressbook_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudAddressBook').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_addressbook_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_addressbook_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_addressbook_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_addressbook_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_addressbook_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_addressbook_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_addressbook_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_addressbook_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_addressbook_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_addressbook_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_addressbook_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_addressbook_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_addressbook_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_bookmarks_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudBookmarks').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_bookmarks_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_bookmarks_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_bookmarks_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_bookmarks_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_bookmarks_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_bookmarks_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_bookmarks_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_bookmarks_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_bookmarks_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_bookmarks_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_bookmarks_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_bookmarks_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_bookmarks_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_calendar_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudCalendar').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_calendar_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_calendar_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_calendar_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_calendar_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_calendar_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_calendar_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_calendar_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_calendar_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_calendar_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_calendar_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_calendar_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_calendar_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_calendar_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_drive_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudDocumentSync').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_drive_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_drive_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_drive_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_drive_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_drive_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_drive_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_drive_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_drive_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_drive_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_drive_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_drive_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_drive_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_drive_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_freeform_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudFreeform').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_freeform_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_freeform_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_freeform_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_freeform_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_freeform_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_freeform_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_freeform_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_freeform_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_freeform_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_freeform_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_freeform_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_freeform_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_freeform_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_game_center_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowGameCenter').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_game_center_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_game_center_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_game_center_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_game_center_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_game_center_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_game_center_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_game_center_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_game_center_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_game_center_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_game_center_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_game_center_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_game_center_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_game_center_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_keychain_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudKeychainSync').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_keychain_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_keychain_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_keychain_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_keychain_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_keychain_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_keychain_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_keychain_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_keychain_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_keychain_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_keychain_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_keychain_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_keychain_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_keychain_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_mail_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudMail').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_mail_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_mail_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_mail_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_mail_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_mail_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_mail_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_mail_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_mail_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_mail_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_mail_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_mail_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_mail_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_mail_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_notes_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudNotes').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_notes_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_notes_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_notes_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_notes_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_notes_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_notes_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_notes_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_notes_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_notes_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_notes_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_notes_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_notes_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_notes_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_photos_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudPhotoLibrary').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_photos_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_photos_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_photos_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_photos_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_photos_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_photos_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_photos_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_photos_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_photos_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_photos_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_photos_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_photos_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_photos_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_private_relay_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudPrivateRelay').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_private_relay_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_private_relay_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_private_relay_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_private_relay_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_private_relay_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_private_relay_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_private_relay_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_private_relay_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_private_relay_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_private_relay_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_private_relay_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_private_relay_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_private_relay_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_reminders_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudReminders').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_reminders_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_reminders_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_reminders_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_reminders_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_reminders_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_reminders_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_reminders_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_reminders_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_reminders_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_reminders_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_reminders_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_reminders_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_reminders_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_sync_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCloudDesktopAndDocuments').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_sync_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('icloud_sync_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_sync_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "icloud_sync_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_sync_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - icloud_sync_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_sync_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_sync_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_sync_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_sync_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_sync_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - icloud_sync_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_sync_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool NO
fi

#####----- Rule: os_account_modification_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowAccountModification').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_account_modification_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_account_modification_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_account_modification_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_account_modification_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_account_modification_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_account_modification_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_account_modification_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_account_modification_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_account_modification_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_account_modification_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_account_modification_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_account_modification_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_account_modification_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_airdrop_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_airdrop_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_airdrop_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_airdrop_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_airdrop_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_airdrop_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_airdrop_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_airdrop_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool NO
fi

#####----- Rule: os_appleid_prompt_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SetupAssistant.managed')\
.objectForKey('SkipCloudSetup').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_appleid_prompt_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_appleid_prompt_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_appleid_prompt_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_appleid_prompt_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_appleid_prompt_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_appleid_prompt_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_appleid_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_appleid_prompt_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_appleid_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_appleid_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_appleid_prompt_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_appleid_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_appleid_prompt_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add finding -bool NO
fi

#####----- Rule: os_asl_log_files_owner_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/stat -f '%Su:%Sg:%N' $(/usr/bin/grep -e '^>' /etc/asl.conf /etc/asl/* | /usr/bin/awk '{ print $2 }') 2> /dev/null | /usr/bin/awk '!/^root:wheel:/{print $1}' | /usr/bin/wc -l | /usr/bin/tr -d ' '
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_asl_log_files_owner_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_asl_log_files_owner_group_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_asl_log_files_owner_group_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_asl_log_files_owner_group_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_asl_log_files_owner_group_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_asl_log_files_owner_group_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_asl_log_files_owner_group_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_asl_log_files_owner_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_asl_log_files_owner_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_asl_log_files_owner_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_asl_log_files_owner_group_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_asl_log_files_owner_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_asl_log_files_owner_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_asl_log_files_owner_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_asl_log_files_owner_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_asl_log_files_owner_group_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_asl_log_files_owner_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_asl_log_files_owner_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_asl_log_files_owner_group_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_asl_log_files_owner_group_configure -dict-add finding -bool NO
fi

#####----- Rule: os_asl_log_files_permissions_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/stat -f '%A:%N' $(/usr/bin/grep -e '^>' /etc/asl.conf /etc/asl/* | /usr/bin/awk '{ print $2 }') 2> /dev/null | /usr/bin/awk '!/640/{print $1}' | /usr/bin/wc -l | /usr/bin/tr -d ' '
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_asl_log_files_permissions_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_asl_log_files_permissions_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_asl_log_files_permissions_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_asl_log_files_permissions_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_asl_log_files_permissions_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_asl_log_files_permissions_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_asl_log_files_permissions_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_asl_log_files_permissions_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_asl_log_files_permissions_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_asl_log_files_permissions_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_asl_log_files_permissions_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_asl_log_files_permissions_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_asl_log_files_permissions_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_asl_log_files_permissions_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_asl_log_files_permissions_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_asl_log_files_permissions_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_asl_log_files_permissions_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_asl_log_files_permissions_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_asl_log_files_permissions_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_asl_log_files_permissions_configure -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_authenticated_root_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_authenticated_root_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_authenticated_root_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_authenticated_root_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_authenticated_root_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_authenticated_root_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_authenticated_root_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_authenticated_root_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool NO
fi

#####----- Rule: os_bonjour_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.mDNSResponder')\
.objectForKey('NoMulticastAdvertisements').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_bonjour_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_bonjour_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_bonjour_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_bonjour_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_bonjour_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_bonjour_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_bonjour_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_bonjour_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_bonjour_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_bonjour_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_bonjour_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_bonjour_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_bonjour_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_bonjour_disable -dict-add finding -bool NO
fi

#####----- Rule: os_camera_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowCamera').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_camera_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_camera_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_camera_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_camera_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_camera_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_camera_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_camera_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_camera_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_camera_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_camera_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_camera_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_camera_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_camera_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_camera_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_camera_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_camera_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_camera_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_camera_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_camera_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_camera_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_config_data_install_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_config_data_install_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_config_data_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_config_data_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_config_data_install_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_config_data_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_config_data_install_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_config_data_install_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool NO
fi

#####----- Rule: os_dictation_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch="i386"
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowDictation').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_dictation_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_dictation_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_dictation_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_dictation_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_dictation_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_dictation_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_dictation_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_dictation_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_dictation_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_dictation_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_dictation_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_dictation_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_dictation_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add finding -bool NO
fi

#####----- Rule: os_directory_services_configured -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/dscl localhost -list . | /usr/bin/grep -qvE '(Contact|Search|Local|^$)'; /bin/echo $?
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_directory_services_configured'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_directory_services_configured'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_directory_services_configured" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_directory_services_configured passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_directory_services_configured -dict-add finding -bool NO
        if [[ ! "$customref" == "os_directory_services_configured" ]]; then
            /usr/bin/defaults write "$audit_plist" os_directory_services_configured -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_directory_services_configured passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_directory_services_configured failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_directory_services_configured -dict-add finding -bool YES
            if [[ ! "$customref" == "os_directory_services_configured" ]]; then
                /usr/bin/defaults write "$audit_plist" os_directory_services_configured -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_directory_services_configured failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_directory_services_configured failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_directory_services_configured -dict-add finding -bool YES
            if [[ ! "$customref" == "os_directory_services_configured" ]]; then
              /usr/bin/defaults write "$audit_plist" os_directory_services_configured -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_directory_services_configured failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_directory_services_configured does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_directory_services_configured -dict-add finding -bool NO
fi

#####----- Rule: os_erase_content_and_settings_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowEraseContentAndSettings').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_erase_content_and_settings_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_erase_content_and_settings_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_erase_content_and_settings_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_erase_content_and_settings_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_erase_content_and_settings_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_erase_content_and_settings_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_erase_content_and_settings_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_erase_content_and_settings_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_erase_content_and_settings_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_erase_content_and_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_erase_content_and_settings_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_erase_content_and_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_erase_content_and_settings_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_erase_content_and_settings_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_erase_content_and_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_erase_content_and_settings_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_erase_content_and_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_erase_content_and_settings_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_erase_content_and_settings_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_erase_content_and_settings_disable -dict-add finding -bool NO
fi

#####----- Rule: os_facetime_app_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let pref1 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess.new')\
  .objectForKey('familyControlsEnabled'))
  let pathlist = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess.new')\
  .objectForKey('pathBlackList').js
  for ( let app in pathlist ) {
      if ( ObjC.unwrap(pathlist[app]) == "/Applications/FaceTime.app" && pref1 == true ){
          return("true")
      }
  }
  return("false")
  }
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_facetime_app_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_facetime_app_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_facetime_app_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_facetime_app_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_facetime_app_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_facetime_app_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_facetime_app_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_facetime_app_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_facetime_app_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_facetime_app_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_facetime_app_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_facetime_app_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_facetime_app_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_facetime_app_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_facetime_app_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_facetime_app_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_facetime_app_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_facetime_app_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_facetime_app_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_facetime_app_disable -dict-add finding -bool NO
fi

#####----- Rule: os_filevault_autologin_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(11)
# * AC-3
# * IA-5(13)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectForKey('DisableFDEAutoLogin').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_filevault_autologin_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_filevault_autologin_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_filevault_autologin_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_filevault_autologin_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_filevault_autologin_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_filevault_autologin_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_filevault_autologin_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_filevault_autologin_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_filevault_autologin_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_filevault_autologin_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_filevault_autologin_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_filevault_autologin_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_filevault_autologin_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add finding -bool NO
fi

#####----- Rule: os_firmware_password_require -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6
rule_arch="i386"
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/firmwarepasswd -check | /usr/bin/grep -c "Password Enabled: Yes"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_firmware_password_require'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_firmware_password_require'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_firmware_password_require" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_firmware_password_require passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add finding -bool NO
        if [[ ! "$customref" == "os_firmware_password_require" ]]; then
            /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_firmware_password_require passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_firmware_password_require failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add finding -bool YES
            if [[ ! "$customref" == "os_firmware_password_require" ]]; then
                /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_firmware_password_require failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_firmware_password_require failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add finding -bool YES
            if [[ ! "$customref" == "os_firmware_password_require" ]]; then
              /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_firmware_password_require failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_firmware_password_require does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_gatekeeper_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_gatekeeper_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_gatekeeper_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_gatekeeper_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_gatekeeper_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_gatekeeper_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_gatekeeper_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_gatekeeper_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool NO
fi

#####----- Rule: os_handoff_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * AC-3
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowActivityContinuation').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_handoff_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_handoff_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_handoff_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_handoff_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_handoff_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_handoff_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_handoff_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_handoff_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_handoff_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_handoff_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_handoff_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_handoff_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_handoff_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_home_folders_secure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_home_folders_secure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_home_folders_secure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_home_folders_secure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_home_folders_secure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_home_folders_secure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_home_folders_secure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_httpd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_httpd_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_httpd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_httpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_httpd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_httpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_httpd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_httpd_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool NO
fi

#####----- Rule: os_icloud_storage_prompt_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SetupAssistant.managed')\
.objectForKey('SkipiCloudStorageSetup').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_icloud_storage_prompt_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_icloud_storage_prompt_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_icloud_storage_prompt_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_icloud_storage_prompt_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_icloud_storage_prompt_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_icloud_storage_prompt_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_icloud_storage_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_icloud_storage_prompt_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_icloud_storage_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_icloud_storage_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_icloud_storage_prompt_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_icloud_storage_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_icloud_storage_prompt_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_install_log_retention_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_install_log_retention_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_install_log_retention_configure passed (Result: $result_value, Expected: "{'string': 'Yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_install_log_retention_configure failed (Result: $result_value, Expected: \"{'string': 'Yes'}\")"
            /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_install_log_retention_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_install_log_retention_configure failed (Result: $result_value, Expected: "{'string': 'Yes'}")"
        else
            logmessage "os_install_log_retention_configure failed (Result: $result_value, Expected: \"{'string': 'Yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_install_log_retention_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_install_log_retention_configure failed (Result: $result_value, Expected: "{'string': 'Yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_install_log_retention_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_install_log_retention_configure -dict-add finding -bool NO
fi

#####----- Rule: os_loginwindow_adminhostinfo_undefined -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.loginwindow')\
.objectIsForcedForKey('AdminHostInfo')
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_loginwindow_adminhostinfo_undefined'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_loginwindow_adminhostinfo_undefined'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_loginwindow_adminhostinfo_undefined" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_loginwindow_adminhostinfo_undefined passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_loginwindow_adminhostinfo_undefined -dict-add finding -bool NO
        if [[ ! "$customref" == "os_loginwindow_adminhostinfo_undefined" ]]; then
            /usr/bin/defaults write "$audit_plist" os_loginwindow_adminhostinfo_undefined -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_loginwindow_adminhostinfo_undefined passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_loginwindow_adminhostinfo_undefined failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_loginwindow_adminhostinfo_undefined -dict-add finding -bool YES
            if [[ ! "$customref" == "os_loginwindow_adminhostinfo_undefined" ]]; then
                /usr/bin/defaults write "$audit_plist" os_loginwindow_adminhostinfo_undefined -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_loginwindow_adminhostinfo_undefined failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_loginwindow_adminhostinfo_undefined failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_loginwindow_adminhostinfo_undefined -dict-add finding -bool YES
            if [[ ! "$customref" == "os_loginwindow_adminhostinfo_undefined" ]]; then
              /usr/bin/defaults write "$audit_plist" os_loginwindow_adminhostinfo_undefined -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_loginwindow_adminhostinfo_undefined failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_loginwindow_adminhostinfo_undefined does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_loginwindow_adminhostinfo_undefined -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_mdm_require'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_mdm_require'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_mdm_require passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_mdm_require failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add finding -bool YES
            if [[ ! "$customref" == "os_mdm_require" ]]; then
                /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_mdm_require failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_mdm_require failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add finding -bool YES
            if [[ ! "$customref" == "os_mdm_require" ]]; then
              /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_mdm_require failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_mdm_require does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_mdm_require -dict-add finding -bool NO
fi

#####----- Rule: os_newsyslog_files_owner_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/stat -f '%Su:%Sg:%N' $(/usr/bin/grep -v '^#' /etc/newsyslog.conf | /usr/bin/awk '{ print $1 }') 2> /dev/null | /usr/bin/awk '!/^root:wheel:/{print $1}' | /usr/bin/wc -l | /usr/bin/tr -d ' '
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_newsyslog_files_owner_group_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_newsyslog_files_owner_group_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_newsyslog_files_owner_group_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_newsyslog_files_owner_group_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_newsyslog_files_owner_group_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_newsyslog_files_owner_group_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_newsyslog_files_owner_group_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_newsyslog_files_owner_group_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_newsyslog_files_owner_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_newsyslog_files_owner_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_newsyslog_files_owner_group_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_newsyslog_files_owner_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_newsyslog_files_owner_group_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_newsyslog_files_owner_group_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_newsyslog_files_owner_group_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_newsyslog_files_owner_group_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_newsyslog_files_owner_group_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_newsyslog_files_owner_group_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_newsyslog_files_owner_group_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_newsyslog_files_owner_group_configure -dict-add finding -bool NO
fi

#####----- Rule: os_newsyslog_files_permissions_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/stat -f '%A:%N' $(/usr/bin/grep -v '^#' /etc/newsyslog.conf | /usr/bin/awk '{ print $1 }') 2> /dev/null | /usr/bin/awk '!/640/{print $1}' | /usr/bin/wc -l | /usr/bin/tr -d ' '
)
    # expected result {'integer': 0}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_newsyslog_files_permissions_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_newsyslog_files_permissions_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_newsyslog_files_permissions_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "0" ]]; then
        logmessage "os_newsyslog_files_permissions_configure passed (Result: $result_value, Expected: \"{'integer': 0}\")"
        /usr/bin/defaults write "$audit_plist" os_newsyslog_files_permissions_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_newsyslog_files_permissions_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_newsyslog_files_permissions_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_newsyslog_files_permissions_configure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_newsyslog_files_permissions_configure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_newsyslog_files_permissions_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_newsyslog_files_permissions_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_newsyslog_files_permissions_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_newsyslog_files_permissions_configure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_newsyslog_files_permissions_configure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_newsyslog_files_permissions_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_newsyslog_files_permissions_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_newsyslog_files_permissions_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_newsyslog_files_permissions_configure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_newsyslog_files_permissions_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_newsyslog_files_permissions_configure -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_nfsd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_nfsd_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_nfsd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_nfsd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_nfsd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_nfsd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_nfsd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_on_device_dictation_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_on_device_dictation_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_on_device_dictation_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_on_device_dictation_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_on_device_dictation_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_on_device_dictation_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_on_device_dictation_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_on_device_dictation_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_on_device_dictation_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_on_device_dictation_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool NO
fi

#####----- Rule: os_password_autofill_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowPasswordAutoFill').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_password_autofill_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_password_autofill_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_password_autofill_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_password_autofill_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_password_autofill_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_password_autofill_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_password_autofill_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_password_autofill_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_password_autofill_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_password_autofill_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_password_autofill_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_password_autofill_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_password_autofill_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_password_autofill_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_password_autofill_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_password_autofill_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_password_autofill_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_password_autofill_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_password_autofill_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_password_autofill_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_password_hint_remove'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_password_hint_remove'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_password_hint_remove passed (Result: $result_value, Expected: "{'string': 'PASS'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_password_hint_remove failed (Result: $result_value, Expected: \"{'string': 'PASS'}\")"
            /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool YES
            if [[ ! "$customref" == "os_password_hint_remove" ]]; then
                /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_password_hint_remove failed (Result: $result_value, Expected: "{'string': 'PASS'}")"
        else
            logmessage "os_password_hint_remove failed (Result: $result_value, Expected: \"{'string': 'PASS'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool YES
            if [[ ! "$customref" == "os_password_hint_remove" ]]; then
              /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_password_hint_remove failed (Result: $result_value, Expected: "{'string': 'PASS'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_password_hint_remove does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_password_hint_remove -dict-add finding -bool NO
fi

#####----- Rule: os_password_proximity_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowPasswordProximityRequests').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_password_proximity_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_password_proximity_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_password_proximity_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_password_proximity_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_password_proximity_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_password_proximity_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_password_proximity_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_password_proximity_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_password_proximity_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_password_proximity_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_password_proximity_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_password_proximity_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_password_proximity_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_password_proximity_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_password_proximity_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_password_proximity_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_password_proximity_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_password_proximity_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_password_proximity_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_password_proximity_disable -dict-add finding -bool NO
fi

#####----- Rule: os_policy_banner_loginwindow_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-8
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/ls -ld /Library/Security/PolicyBanner.rtf* | /usr/bin/wc -l | /usr/bin/tr -d ' '
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_loginwindow_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_loginwindow_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_policy_banner_loginwindow_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_policy_banner_loginwindow_enforce passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_policy_banner_loginwindow_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "os_policy_banner_loginwindow_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" os_policy_banner_loginwindow_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_policy_banner_loginwindow_enforce passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_policy_banner_loginwindow_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_policy_banner_loginwindow_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_policy_banner_loginwindow_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" os_policy_banner_loginwindow_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_policy_banner_loginwindow_enforce failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_policy_banner_loginwindow_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_policy_banner_loginwindow_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_policy_banner_loginwindow_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" os_policy_banner_loginwindow_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_policy_banner_loginwindow_enforce failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_policy_banner_loginwindow_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_policy_banner_loginwindow_enforce -dict-add finding -bool NO
fi

#####----- Rule: os_policy_banner_ssh_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-8
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(bannerText="You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only.

By using this IS (which includes any device attached to this IS), you consent to the following conditions:

-The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations and defense, personnel misconduct (PM), law enforcement (LE), and counterintelligence (CI) investigations.

-At any time, the USG may inspect and seize data stored on this IS.

-Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose.

-This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy.

-Notwithstanding the above, using this IS does not constitute consent to PM, LE or CI investigative searching or monitoring of the content of privileged communications, or work product, related to personal representation or services by attorneys, psychotherapists, or clergy, and their assistants. Such communications and work product are private and confidential. See User Agreement for details."
test "$(cat /etc/banner)" = "$bannerText" && echo "1" || echo "0"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_ssh_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_ssh_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_policy_banner_ssh_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_policy_banner_ssh_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_policy_banner_ssh_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_policy_banner_ssh_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_policy_banner_ssh_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_policy_banner_ssh_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_policy_banner_ssh_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_policy_banner_ssh_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_policy_banner_ssh_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_policy_banner_ssh_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_policy_banner_ssh_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_configure -dict-add finding -bool NO
fi

#####----- Rule: os_policy_banner_ssh_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-8
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/sshd -G | /usr/bin/grep -c "^banner /etc/banner"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_ssh_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_ssh_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_policy_banner_ssh_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_policy_banner_ssh_enforce passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "os_policy_banner_ssh_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_policy_banner_ssh_enforce passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_policy_banner_ssh_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_policy_banner_ssh_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_policy_banner_ssh_enforce failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_policy_banner_ssh_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_policy_banner_ssh_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_policy_banner_ssh_enforce failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_policy_banner_ssh_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_policy_banner_ssh_enforce -dict-add finding -bool NO
fi

#####----- Rule: os_privacy_setup_prompt_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SetupAssistant.managed')\
.objectForKey('SkipPrivacySetup').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_privacy_setup_prompt_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_privacy_setup_prompt_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_privacy_setup_prompt_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_privacy_setup_prompt_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_privacy_setup_prompt_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_privacy_setup_prompt_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_privacy_setup_prompt_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_privacy_setup_prompt_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_privacy_setup_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_privacy_setup_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_privacy_setup_prompt_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_privacy_setup_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_privacy_setup_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_privacy_setup_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_privacy_setup_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_privacy_setup_prompt_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_privacy_setup_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_privacy_setup_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_privacy_setup_prompt_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_privacy_setup_prompt_disable -dict-add finding -bool NO
fi

#####----- Rule: os_recovery_lock_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6
rule_arch="arm64"
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/libexec/mdmclient QuerySecurityInfo | /usr/bin/grep -c "IsRecoveryLockEnabled = 1"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_recovery_lock_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_recovery_lock_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_recovery_lock_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_recovery_lock_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_recovery_lock_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_recovery_lock_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_recovery_lock_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_recovery_lock_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_recovery_lock_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_recovery_lock_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_recovery_lock_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_recovery_lock_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_recovery_lock_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_root_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_root_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_root_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_root_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_root_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_root_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_root_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_root_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool NO
fi

#####----- Rule: os_secure_boot_verify -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-6
# * SI-7, SI-7(1), SI-7(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/libexec/mdmclient QuerySecurityInfo | /usr/bin/grep -c "SecureBootLevel = full"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_secure_boot_verify'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_secure_boot_verify'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_secure_boot_verify" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_secure_boot_verify passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_secure_boot_verify -dict-add finding -bool NO
        if [[ ! "$customref" == "os_secure_boot_verify" ]]; then
            /usr/bin/defaults write "$audit_plist" os_secure_boot_verify -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_secure_boot_verify passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_secure_boot_verify failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_secure_boot_verify -dict-add finding -bool YES
            if [[ ! "$customref" == "os_secure_boot_verify" ]]; then
                /usr/bin/defaults write "$audit_plist" os_secure_boot_verify -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_secure_boot_verify failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_secure_boot_verify failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_secure_boot_verify -dict-add finding -bool YES
            if [[ ! "$customref" == "os_secure_boot_verify" ]]; then
              /usr/bin/defaults write "$audit_plist" os_secure_boot_verify -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_secure_boot_verify failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_secure_boot_verify does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_secure_boot_verify -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sip_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sip_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_sip_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sip_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sip_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_sip_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sip_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sip_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool NO
fi

#####----- Rule: os_siri_prompt_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SetupAssistant.managed')\
.objectForKey('SkipSiriSetup').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_siri_prompt_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_siri_prompt_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_siri_prompt_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_siri_prompt_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_siri_prompt_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_siri_prompt_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_siri_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_siri_prompt_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_siri_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_siri_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_siri_prompt_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_siri_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_siri_prompt_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add finding -bool NO
fi

#####----- Rule: os_skip_screen_time_prompt_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SetupAssistant.managed')\
.objectForKey('SkipScreenTime').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_skip_screen_time_prompt_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_skip_screen_time_prompt_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_skip_screen_time_prompt_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_skip_screen_time_prompt_enable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_skip_screen_time_prompt_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_skip_screen_time_prompt_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_skip_screen_time_prompt_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_skip_screen_time_prompt_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_skip_screen_time_prompt_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_skip_screen_time_prompt_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_skip_screen_time_prompt_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_skip_screen_time_prompt_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_skip_screen_time_prompt_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_skip_screen_time_prompt_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_skip_screen_time_prompt_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_skip_screen_time_prompt_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_skip_screen_time_prompt_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_skip_screen_time_prompt_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_skip_screen_time_prompt_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_skip_screen_time_prompt_enable -dict-add finding -bool NO
fi

#####----- Rule: os_skip_unlock_with_watch_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SetupAssistant.managed')\
.objectForKey('SkipUnlockWithWatch').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_skip_unlock_with_watch_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_skip_unlock_with_watch_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_skip_unlock_with_watch_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_skip_unlock_with_watch_enable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_skip_unlock_with_watch_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_skip_unlock_with_watch_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_skip_unlock_with_watch_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_skip_unlock_with_watch_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_skip_unlock_with_watch_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_skip_unlock_with_watch_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_skip_unlock_with_watch_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_skip_unlock_with_watch_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_skip_unlock_with_watch_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add finding -bool NO
fi

#####----- Rule: os_ssh_fips_compliant -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17(2)
# * IA-7
# * SC-13
# * SC-8(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(fips_ssh_config="Host *
Ciphers aes128-gcm@openssh.com
HostbasedAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
KexAlgorithms ecdh-sha2-nistp256
MACs hmac-sha2-256
PubkeyAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
CASignatureAlgorithms ecdsa-sha2-nistp256"
/usr/bin/grep -c "$fips_ssh_config" /etc/ssh/ssh_config.d/fips_ssh_config
)
    # expected result {'integer': 8}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_fips_compliant'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_fips_compliant'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_ssh_fips_compliant" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "8" ]]; then
        logmessage "os_ssh_fips_compliant passed (Result: $result_value, Expected: \"{'integer': 8}\")"
        /usr/bin/defaults write "$audit_plist" os_ssh_fips_compliant -dict-add finding -bool NO
        if [[ ! "$customref" == "os_ssh_fips_compliant" ]]; then
            /usr/bin/defaults write "$audit_plist" os_ssh_fips_compliant -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_ssh_fips_compliant passed (Result: $result_value, Expected: "{'integer': 8}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_ssh_fips_compliant failed (Result: $result_value, Expected: \"{'integer': 8}\")"
            /usr/bin/defaults write "$audit_plist" os_ssh_fips_compliant -dict-add finding -bool YES
            if [[ ! "$customref" == "os_ssh_fips_compliant" ]]; then
                /usr/bin/defaults write "$audit_plist" os_ssh_fips_compliant -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_ssh_fips_compliant failed (Result: $result_value, Expected: "{'integer': 8}")"
        else
            logmessage "os_ssh_fips_compliant failed (Result: $result_value, Expected: \"{'integer': 8}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_ssh_fips_compliant -dict-add finding -bool YES
            if [[ ! "$customref" == "os_ssh_fips_compliant" ]]; then
              /usr/bin/defaults write "$audit_plist" os_ssh_fips_compliant -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_ssh_fips_compliant failed (Result: $result_value, Expected: "{'integer': 8}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_ssh_fips_compliant does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_ssh_fips_compliant -dict-add finding -bool NO
fi

#####----- Rule: os_ssh_server_alive_count_max_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SC-10
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(ret="pass"
for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 > 500 {print $1}'); do
  sshCheck=$(/usr/bin/sudo -u $u /usr/bin/ssh -G . | /usr/bin/grep -c "^serveralivecountmax 0")
  if [[ "$sshCheck" == "0" ]]; then
    ret="fail"
    break
  fi
done
/bin/echo $ret
)
    # expected result {'string': 'pass'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_server_alive_count_max_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_server_alive_count_max_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_ssh_server_alive_count_max_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "pass" ]]; then
        logmessage "os_ssh_server_alive_count_max_configure passed (Result: $result_value, Expected: \"{'string': 'pass'}\")"
        /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_count_max_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_ssh_server_alive_count_max_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_count_max_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_ssh_server_alive_count_max_configure passed (Result: $result_value, Expected: "{'string': 'pass'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_ssh_server_alive_count_max_configure failed (Result: $result_value, Expected: \"{'string': 'pass'}\")"
            /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_count_max_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_ssh_server_alive_count_max_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_count_max_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_ssh_server_alive_count_max_configure failed (Result: $result_value, Expected: "{'string': 'pass'}")"
        else
            logmessage "os_ssh_server_alive_count_max_configure failed (Result: $result_value, Expected: \"{'string': 'pass'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_count_max_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_ssh_server_alive_count_max_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_count_max_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_ssh_server_alive_count_max_configure failed (Result: $result_value, Expected: "{'string': 'pass'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_ssh_server_alive_count_max_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_count_max_configure -dict-add finding -bool NO
fi

#####----- Rule: os_ssh_server_alive_interval_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * SC-10
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(ret="pass"
for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 > 500 {print $1}'); do
  sshCheck=$(/usr/bin/sudo -u $u /usr/bin/ssh -G . | /usr/bin/grep -c "^serveraliveinterval 900")
  if [[ "$sshCheck" == "0" ]]; then
    ret="fail"
    break
  fi
done
/bin/echo $ret
)
    # expected result {'string': 'pass'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_server_alive_interval_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_server_alive_interval_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_ssh_server_alive_interval_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "pass" ]]; then
        logmessage "os_ssh_server_alive_interval_configure passed (Result: $result_value, Expected: \"{'string': 'pass'}\")"
        /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_interval_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_ssh_server_alive_interval_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_interval_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_ssh_server_alive_interval_configure passed (Result: $result_value, Expected: "{'string': 'pass'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_ssh_server_alive_interval_configure failed (Result: $result_value, Expected: \"{'string': 'pass'}\")"
            /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_interval_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_ssh_server_alive_interval_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_interval_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_ssh_server_alive_interval_configure failed (Result: $result_value, Expected: "{'string': 'pass'}")"
        else
            logmessage "os_ssh_server_alive_interval_configure failed (Result: $result_value, Expected: \"{'string': 'pass'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_interval_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_ssh_server_alive_interval_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_interval_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_ssh_server_alive_interval_configure failed (Result: $result_value, Expected: "{'string': 'pass'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_ssh_server_alive_interval_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_ssh_server_alive_interval_configure -dict-add finding -bool NO
fi

#####----- Rule: os_sshd_channel_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * SC-10
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/sshd -G | /usr/bin/awk -F "=" '/channeltimeout session:*/{print $2}'
)
    # expected result {'integer': 900}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_channel_timeout_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_channel_timeout_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sshd_channel_timeout_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "900" ]]; then
        logmessage "os_sshd_channel_timeout_configure passed (Result: $result_value, Expected: \"{'integer': 900}\")"
        /usr/bin/defaults write "$audit_plist" os_sshd_channel_timeout_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sshd_channel_timeout_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sshd_channel_timeout_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_sshd_channel_timeout_configure passed (Result: $result_value, Expected: "{'integer': 900}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sshd_channel_timeout_configure failed (Result: $result_value, Expected: \"{'integer': 900}\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_channel_timeout_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_channel_timeout_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sshd_channel_timeout_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_channel_timeout_configure failed (Result: $result_value, Expected: "{'integer': 900}")"
        else
            logmessage "os_sshd_channel_timeout_configure failed (Result: $result_value, Expected: \"{'integer': 900}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_channel_timeout_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_channel_timeout_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sshd_channel_timeout_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_channel_timeout_configure failed (Result: $result_value, Expected: "{'integer': 900}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sshd_channel_timeout_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sshd_channel_timeout_configure -dict-add finding -bool NO
fi

#####----- Rule: os_sshd_client_alive_count_max_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SC-10
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/sshd -G | /usr/bin/awk '/clientalivecountmax/{print $2}'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_client_alive_count_max_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_client_alive_count_max_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sshd_client_alive_count_max_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_sshd_client_alive_count_max_configure passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_count_max_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sshd_client_alive_count_max_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_count_max_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_sshd_client_alive_count_max_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sshd_client_alive_count_max_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_count_max_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_client_alive_count_max_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_count_max_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_client_alive_count_max_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_sshd_client_alive_count_max_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_count_max_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_client_alive_count_max_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_count_max_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_client_alive_count_max_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sshd_client_alive_count_max_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_count_max_configure -dict-add finding -bool NO
fi

#####----- Rule: os_sshd_client_alive_interval_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * SC-10
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/sshd -G | /usr/bin/awk '/clientaliveinterval/{print $2}'
)
    # expected result {'integer': 900}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_client_alive_interval_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_client_alive_interval_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sshd_client_alive_interval_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "900" ]]; then
        logmessage "os_sshd_client_alive_interval_configure passed (Result: $result_value, Expected: \"{'integer': 900}\")"
        /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_interval_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sshd_client_alive_interval_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_interval_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_sshd_client_alive_interval_configure passed (Result: $result_value, Expected: "{'integer': 900}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sshd_client_alive_interval_configure failed (Result: $result_value, Expected: \"{'integer': 900}\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_interval_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_client_alive_interval_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_interval_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_client_alive_interval_configure failed (Result: $result_value, Expected: "{'integer': 900}")"
        else
            logmessage "os_sshd_client_alive_interval_configure failed (Result: $result_value, Expected: \"{'integer': 900}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_interval_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_client_alive_interval_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_interval_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_client_alive_interval_configure failed (Result: $result_value, Expected: "{'integer': 900}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sshd_client_alive_interval_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sshd_client_alive_interval_configure -dict-add finding -bool NO
fi

#####----- Rule: os_sshd_fips_compliant -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17(2)
# * IA-7
# * SC-13
# * SC-8(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(fips_sshd_config=("Ciphers aes128-gcm@openssh.com" "HostbasedAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "KexAlgorithms ecdh-sha2-nistp256" "MACs hmac-sha2-256" "PubkeyAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "CASignatureAlgorithms ecdsa-sha2-nistp256")
total=0
for config in $fips_sshd_config; do
  total=$(expr $(/usr/sbin/sshd -G | /usr/bin/grep -i -c "$config") + $total)
done

echo $total
)
    # expected result {'integer': 7}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_fips_compliant'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_fips_compliant'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sshd_fips_compliant" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "7" ]]; then
        logmessage "os_sshd_fips_compliant passed (Result: $result_value, Expected: \"{'integer': 7}\")"
        /usr/bin/defaults write "$audit_plist" os_sshd_fips_compliant -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sshd_fips_compliant" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sshd_fips_compliant -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_sshd_fips_compliant passed (Result: $result_value, Expected: "{'integer': 7}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sshd_fips_compliant failed (Result: $result_value, Expected: \"{'integer': 7}\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_fips_compliant -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_fips_compliant" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sshd_fips_compliant -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_fips_compliant failed (Result: $result_value, Expected: "{'integer': 7}")"
        else
            logmessage "os_sshd_fips_compliant failed (Result: $result_value, Expected: \"{'integer': 7}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_fips_compliant -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_fips_compliant" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sshd_fips_compliant -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_fips_compliant failed (Result: $result_value, Expected: "{'integer': 7}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sshd_fips_compliant does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sshd_fips_compliant -dict-add finding -bool NO
fi

#####----- Rule: os_sshd_login_grace_time_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SC-10
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/sshd -G | /usr/bin/awk '/logingracetime/{print $2}'
)
    # expected result {'integer': 30}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_login_grace_time_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_login_grace_time_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sshd_login_grace_time_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "30" ]]; then
        logmessage "os_sshd_login_grace_time_configure passed (Result: $result_value, Expected: \"{'integer': 30}\")"
        /usr/bin/defaults write "$audit_plist" os_sshd_login_grace_time_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sshd_login_grace_time_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sshd_login_grace_time_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_sshd_login_grace_time_configure passed (Result: $result_value, Expected: "{'integer': 30}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sshd_login_grace_time_configure failed (Result: $result_value, Expected: \"{'integer': 30}\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_login_grace_time_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_login_grace_time_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sshd_login_grace_time_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_login_grace_time_configure failed (Result: $result_value, Expected: "{'integer': 30}")"
        else
            logmessage "os_sshd_login_grace_time_configure failed (Result: $result_value, Expected: \"{'integer': 30}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_login_grace_time_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_login_grace_time_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sshd_login_grace_time_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_login_grace_time_configure failed (Result: $result_value, Expected: "{'integer': 30}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sshd_login_grace_time_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sshd_login_grace_time_configure -dict-add finding -bool NO
fi

#####----- Rule: os_sshd_permit_root_login_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/sshd -G | /usr/bin/awk '/permitrootlogin/{print $2}'
)
    # expected result {'string': 'no'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_permit_root_login_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_permit_root_login_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sshd_permit_root_login_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "no" ]]; then
        logmessage "os_sshd_permit_root_login_configure passed (Result: $result_value, Expected: \"{'string': 'no'}\")"
        /usr/bin/defaults write "$audit_plist" os_sshd_permit_root_login_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sshd_permit_root_login_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sshd_permit_root_login_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_sshd_permit_root_login_configure passed (Result: $result_value, Expected: "{'string': 'no'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sshd_permit_root_login_configure failed (Result: $result_value, Expected: \"{'string': 'no'}\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_permit_root_login_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_permit_root_login_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sshd_permit_root_login_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_permit_root_login_configure failed (Result: $result_value, Expected: "{'string': 'no'}")"
        else
            logmessage "os_sshd_permit_root_login_configure failed (Result: $result_value, Expected: \"{'string': 'no'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_permit_root_login_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_permit_root_login_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sshd_permit_root_login_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_permit_root_login_configure failed (Result: $result_value, Expected: "{'string': 'no'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sshd_permit_root_login_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sshd_permit_root_login_configure -dict-add finding -bool NO
fi

#####----- Rule: os_sshd_unused_connection_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * SC-10
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/sshd -G | /usr/bin/awk '/unusedconnectiontimeout/{print $2}'
)
    # expected result {'integer': 900}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_unused_connection_timeout_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_unused_connection_timeout_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_sshd_unused_connection_timeout_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "900" ]]; then
        logmessage "os_sshd_unused_connection_timeout_configure passed (Result: $result_value, Expected: \"{'integer': 900}\")"
        /usr/bin/defaults write "$audit_plist" os_sshd_unused_connection_timeout_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "os_sshd_unused_connection_timeout_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" os_sshd_unused_connection_timeout_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_sshd_unused_connection_timeout_configure passed (Result: $result_value, Expected: "{'integer': 900}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sshd_unused_connection_timeout_configure failed (Result: $result_value, Expected: \"{'integer': 900}\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_unused_connection_timeout_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_unused_connection_timeout_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sshd_unused_connection_timeout_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_unused_connection_timeout_configure failed (Result: $result_value, Expected: "{'integer': 900}")"
        else
            logmessage "os_sshd_unused_connection_timeout_configure failed (Result: $result_value, Expected: \"{'integer': 900}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sshd_unused_connection_timeout_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sshd_unused_connection_timeout_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sshd_unused_connection_timeout_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sshd_unused_connection_timeout_configure failed (Result: $result_value, Expected: "{'integer': 900}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sshd_unused_connection_timeout_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sshd_unused_connection_timeout_configure -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sudo_timeout_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sudo_timeout_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_sudo_timeout_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sudo_timeout_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sudo_timeout_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sudo_timeout_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_sudo_timeout_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sudo_timeout_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sudo_timeout_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sudo_timeout_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_sudoers_timestamp_type_configure passed (Result: $result_value, Expected: "{'string': 'tty'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: \"{'string': 'tty'}\")"
            /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sudoers_timestamp_type_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: "{'string': 'tty'}")"
        else
            logmessage "os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: \"{'string': 'tty'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sudoers_timestamp_type_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_sudoers_timestamp_type_configure failed (Result: $result_value, Expected: "{'string': 'tty'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_sudoers_timestamp_type_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_sudoers_timestamp_type_configure -dict-add finding -bool NO
fi

#####----- Rule: os_tftpd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
# * IA-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.tftpd" => disabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_tftpd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_tftpd_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_tftpd_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_tftpd_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_tftpd_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_tftpd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_tftpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_tftpd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_tftpd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_tftpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_tftpd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_tftpd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_tftpd_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_time_server_enabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_time_server_enabled'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_time_server_enabled passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_time_server_enabled failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "os_time_server_enabled" ]]; then
                /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_time_server_enabled failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_time_server_enabled failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add finding -bool YES
            if [[ ! "$customref" == "os_time_server_enabled" ]]; then
              /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_time_server_enabled failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_time_server_enabled does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_time_server_enabled -dict-add finding -bool NO
fi

#####----- Rule: os_touchid_prompt_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-6
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.SetupAssistant.managed')\
.objectForKey('SkipTouchIDSetup').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_touchid_prompt_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_touchid_prompt_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_touchid_prompt_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_touchid_prompt_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_touchid_prompt_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_touchid_prompt_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_touchid_prompt_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_touchid_prompt_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_touchid_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_touchid_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_touchid_prompt_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_touchid_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_touchid_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_touchid_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_touchid_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_touchid_prompt_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_touchid_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_touchid_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_touchid_prompt_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_touchid_prompt_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - os_unlock_active_user_session_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_unlock_active_user_session_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_unlock_active_user_session_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_unlock_active_user_session_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_unlock_active_user_session_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_unlock_active_user_session_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool NO
fi

#####----- Rule: os_user_app_installation_prohibit -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-11(2)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let pref1 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess.new')\
  .objectForKey('familyControlsEnabled'))
  let pathlist = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess.new')\
  .objectForKey('pathBlackList').js
  for ( let app in pathlist ) {
      if ( ObjC.unwrap(pathlist[app]) == "/Users/" && pref1 == true ){
          return("true")
      }
  }
  return("false")
  }
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_user_app_installation_prohibit'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_user_app_installation_prohibit'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_user_app_installation_prohibit" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_user_app_installation_prohibit passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_user_app_installation_prohibit -dict-add finding -bool NO
        if [[ ! "$customref" == "os_user_app_installation_prohibit" ]]; then
            /usr/bin/defaults write "$audit_plist" os_user_app_installation_prohibit -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_user_app_installation_prohibit passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_user_app_installation_prohibit failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_user_app_installation_prohibit -dict-add finding -bool YES
            if [[ ! "$customref" == "os_user_app_installation_prohibit" ]]; then
                /usr/bin/defaults write "$audit_plist" os_user_app_installation_prohibit -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_user_app_installation_prohibit failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_user_app_installation_prohibit failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_user_app_installation_prohibit -dict-add finding -bool YES
            if [[ ! "$customref" == "os_user_app_installation_prohibit" ]]; then
              /usr/bin/defaults write "$audit_plist" os_user_app_installation_prohibit -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_user_app_installation_prohibit failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_user_app_installation_prohibit does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_user_app_installation_prohibit -dict-add finding -bool NO
fi

#####----- Rule: os_uucp_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.apple.uucp" => disabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_uucp_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_uucp_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_uucp_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "os_uucp_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_uucp_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - os_uucp_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_uucp_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_uucp_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_uucp_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_uucp_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_uucp_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - os_uucp_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_uucp_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_account_inactivity_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(3)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyAttributeInactiveDays"]/following-sibling::integer[1]/text()' -
)
    # expected result {'integer': 35}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_account_inactivity_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_account_inactivity_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_account_inactivity_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "35" ]]; then
        logmessage "pwpolicy_account_inactivity_enforce passed (Result: $result_value, Expected: \"{'integer': 35}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_account_inactivity_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_account_inactivity_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_inactivity_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - pwpolicy_account_inactivity_enforce passed (Result: $result_value, Expected: "{'integer': 35}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_account_inactivity_enforce failed (Result: $result_value, Expected: \"{'integer': 35}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_inactivity_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_inactivity_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_account_inactivity_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_account_inactivity_enforce failed (Result: $result_value, Expected: "{'integer': 35}")"
        else
            logmessage "pwpolicy_account_inactivity_enforce failed (Result: $result_value, Expected: \"{'integer': 35}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_inactivity_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_inactivity_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_account_inactivity_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_account_inactivity_enforce failed (Result: $result_value, Expected: "{'integer': 35}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_account_inactivity_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_account_inactivity_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_account_lockout_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyAttributeMaximumFailedAuthentications"]/following-sibling::integer[1]/text()' - | /usr/bin/awk '{ if ($1 <= 3) {print "yes"} else {print "no"}}'
)
    # expected result {'string': 'yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_account_lockout_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_account_lockout_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - pwpolicy_account_lockout_enforce passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_account_lockout_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_lockout_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_account_lockout_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            logmessage "pwpolicy_account_lockout_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_lockout_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_account_lockout_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_account_lockout_timeout_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_account_lockout_timeout_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - pwpolicy_account_lockout_timeout_enforce passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_account_lockout_timeout_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_lockout_timeout_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_account_lockout_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            logmessage "pwpolicy_account_lockout_timeout_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_account_lockout_timeout_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_account_lockout_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_account_lockout_timeout_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_account_lockout_timeout_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_alpha_numeric_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyIdentifier"]/following-sibling::*[1]/text()' - | /usr/bin/grep "requireAlphanumeric" -c
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_alpha_numeric_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_alpha_numeric_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_alpha_numeric_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "pwpolicy_alpha_numeric_enforce passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_alpha_numeric_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_alpha_numeric_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_alpha_numeric_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - pwpolicy_alpha_numeric_enforce passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_alpha_numeric_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_alpha_numeric_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_alpha_numeric_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_alpha_numeric_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_alpha_numeric_enforce failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "pwpolicy_alpha_numeric_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_alpha_numeric_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_alpha_numeric_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_alpha_numeric_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_alpha_numeric_enforce failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_alpha_numeric_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_alpha_numeric_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_custom_regex_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath 'boolean(//*[contains(text(),"policyAttributePassword matches '\''^(?=.*[A-Z])(?=.*[a-z]).*$'\''")])' -
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_custom_regex_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_custom_regex_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_custom_regex_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "pwpolicy_custom_regex_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_custom_regex_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_custom_regex_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_custom_regex_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - pwpolicy_custom_regex_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_custom_regex_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_custom_regex_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_custom_regex_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_custom_regex_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_custom_regex_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "pwpolicy_custom_regex_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_custom_regex_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_custom_regex_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_custom_regex_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_custom_regex_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_custom_regex_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_custom_regex_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_history_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyAttributePasswordHistoryDepth"]/following-sibling::*[1]/text()' - | /usr/bin/awk '{ if ($1 >= 5 ) {print "yes"} else {print "no"}}'
)
    # expected result {'string': 'yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_history_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_history_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - pwpolicy_history_enforce passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_history_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_history_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_history_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            logmessage "pwpolicy_history_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_history_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_history_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_history_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
    # expected result {'integer': 60}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_max_lifetime_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_max_lifetime_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_max_lifetime_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "60" ]]; then
        logmessage "pwpolicy_max_lifetime_enforce passed (Result: $result_value, Expected: \"{'integer': 60}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_max_lifetime_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - pwpolicy_max_lifetime_enforce passed (Result: $result_value, Expected: "{'integer': 60}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_max_lifetime_enforce failed (Result: $result_value, Expected: \"{'integer': 60}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_max_lifetime_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_max_lifetime_enforce failed (Result: $result_value, Expected: "{'integer': 60}")"
        else
            logmessage "pwpolicy_max_lifetime_enforce failed (Result: $result_value, Expected: \"{'integer': 60}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_max_lifetime_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_max_lifetime_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_max_lifetime_enforce failed (Result: $result_value, Expected: "{'integer': 60}") - Exemption Allowed (Reason: "$exempt_reason")"
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
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath 'boolean(//*[contains(text(),"policyAttributePassword matches '\''.{14,}'\''")])' -
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_minimum_length_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_minimum_length_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - pwpolicy_minimum_length_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_minimum_length_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_minimum_length_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_minimum_length_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "pwpolicy_minimum_length_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_minimum_length_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_minimum_length_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_minimum_length_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_length_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_minimum_lifetime_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath '//dict/key[text()="policyAttributeMinimumLifetimeHours"]/following-sibling::integer[1]/text()' - | /usr/bin/awk '{ if ($1 >= 24 ) {print "yes"} else {print "no"}}'
)
    # expected result {'string': 'yes'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_minimum_lifetime_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_minimum_lifetime_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_minimum_lifetime_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "yes" ]]; then
        logmessage "pwpolicy_minimum_lifetime_enforce passed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_lifetime_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_minimum_lifetime_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_lifetime_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - pwpolicy_minimum_lifetime_enforce passed (Result: $result_value, Expected: "{'string': 'yes'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_minimum_lifetime_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_lifetime_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_minimum_lifetime_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_lifetime_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_minimum_lifetime_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}")"
        else
            logmessage "pwpolicy_minimum_lifetime_enforce failed (Result: $result_value, Expected: \"{'string': 'yes'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_lifetime_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_minimum_lifetime_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_lifetime_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_minimum_lifetime_enforce failed (Result: $result_value, Expected: "{'string': 'yes'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_minimum_lifetime_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_minimum_lifetime_enforce -dict-add finding -bool NO
fi

#####----- Rule: pwpolicy_special_character_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/pwpolicy -getaccountpolicies 2> /dev/null | /usr/bin/tail +2 | /usr/bin/xmllint --xpath 'boolean(//*[contains(text(),"policyAttributePassword matches '\''(.*[^a-zA-Z0-9].*){1,}'\''")])' -
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_special_character_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_special_character_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "pwpolicy_special_character_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "pwpolicy_special_character_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" pwpolicy_special_character_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "pwpolicy_special_character_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" pwpolicy_special_character_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - pwpolicy_special_character_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "pwpolicy_special_character_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_special_character_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_special_character_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" pwpolicy_special_character_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_special_character_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "pwpolicy_special_character_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" pwpolicy_special_character_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "pwpolicy_special_character_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" pwpolicy_special_character_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - pwpolicy_special_character_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "pwpolicy_special_character_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" pwpolicy_special_character_enforce -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_airplay_receiver_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_airplay_receiver_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_airplay_receiver_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_airplay_receiver_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_airplay_receiver_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_airplay_receiver_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_airplay_receiver_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_airplay_receiver_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_airplay_receiver_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_airplay_receiver_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_airplay_receiver_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_apple_watch_unlock_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowAutoUnlock').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_apple_watch_unlock_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_apple_watch_unlock_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_apple_watch_unlock_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "system_settings_apple_watch_unlock_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_apple_watch_unlock_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_apple_watch_unlock_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_apple_watch_unlock_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_apple_watch_unlock_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_apple_watch_unlock_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_apple_watch_unlock_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_apple_watch_unlock_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_apple_watch_unlock_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_apple_watch_unlock_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_apple_watch_unlock_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_apple_watch_unlock_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_apple_watch_unlock_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_apple_watch_unlock_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_apple_watch_unlock_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_apple_watch_unlock_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_apple_watch_unlock_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_automatic_login_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_automatic_login_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_automatic_login_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_automatic_login_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_automatic_login_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_automatic_login_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_automatic_login_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_automatic_login_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_automatic_logout_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * AC-2(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('.GlobalPreferences')\
.objectForKey('com.apple.autologout.AutoLogOutDelay').js
EOS
)
    # expected result {'integer': 86400}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_automatic_logout_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_automatic_logout_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_automatic_logout_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "86400" ]]; then
        logmessage "system_settings_automatic_logout_enforce passed (Result: $result_value, Expected: \"{'integer': 86400}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_automatic_logout_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_automatic_logout_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_logout_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_automatic_logout_enforce passed (Result: $result_value, Expected: "{'integer': 86400}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_automatic_logout_enforce failed (Result: $result_value, Expected: \"{'integer': 86400}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_logout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_automatic_logout_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_automatic_logout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_automatic_logout_enforce failed (Result: $result_value, Expected: "{'integer': 86400}")"
        else
            logmessage "system_settings_automatic_logout_enforce failed (Result: $result_value, Expected: \"{'integer': 86400}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_logout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_automatic_logout_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_automatic_logout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_automatic_logout_enforce failed (Result: $result_value, Expected: "{'integer': 86400}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_automatic_logout_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_automatic_logout_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_bluetooth_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-18, AC-18(3)
# * SC-8
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.MCXBluetooth')\
.objectForKey('DisableBluetooth').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_bluetooth_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_bluetooth_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_bluetooth_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_bluetooth_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_bluetooth_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_bluetooth_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_bluetooth_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_bluetooth_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_bluetooth_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_bluetooth_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_bluetooth_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_bluetooth_settings_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles show -output stdout-xml | /usr/bin/xmllint --xpath '//key[text()="DisabledSystemSettings"]/following-sibling::*[1]' - | /usr/bin/grep -c com.apple.BluetoothSettings
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_bluetooth_settings_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_bluetooth_settings_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_bluetooth_settings_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_bluetooth_settings_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_settings_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_bluetooth_settings_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_settings_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_bluetooth_settings_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_bluetooth_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_settings_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_bluetooth_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_bluetooth_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_settings_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_bluetooth_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_bluetooth_settings_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_settings_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_bluetooth_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}")"
        else
            logmessage "system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_cd_dvd_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_cd_dvd_sharing_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_cd_dvd_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_cd_dvd_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_cd_dvd_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_cd_dvd_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_cd_dvd_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_cd_dvd_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_cd_dvd_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_cd_dvd_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_cd_dvd_sharing_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_content_caching_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowContentCaching').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_content_caching_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_content_caching_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_content_caching_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "system_settings_content_caching_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_content_caching_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_content_caching_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_content_caching_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_content_caching_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_content_caching_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_content_caching_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_content_caching_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_content_caching_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_content_caching_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_content_caching_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_content_caching_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_content_caching_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_content_caching_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_content_caching_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_content_caching_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_content_caching_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_diagnostics_reports_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * SC-7(10)
# * SI-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
let pref1 = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.SubmitDiagInfo')\
.objectForKey('AutoSubmit').js
let pref2 = $.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowDiagnosticSubmission').js
if ( pref1 == false && pref2 == false ){
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_diagnostics_reports_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_diagnostics_reports_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_diagnostics_reports_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_diagnostics_reports_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_diagnostics_reports_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_diagnostics_reports_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_diagnostics_reports_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_diagnostics_reports_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_diagnostics_reports_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_diagnostics_reports_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_diagnostics_reports_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_diagnostics_reports_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_diagnostics_reports_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_filevault_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_filevault_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_filevault_enforce passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_filevault_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_filevault_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_filevault_enforce failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_filevault_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_filevault_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_filevault_enforce failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_filevault_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_filevault_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_find_my_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let pref1 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowFindMyDevice'))
  let pref2 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowFindMyFriends'))
  let pref3 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.icloud.managed')\
.objectForKey('DisableFMMiCloudSetting'))
  if ( pref1 == false && pref2 == false && pref3 == true ) {
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_find_my_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_find_my_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_find_my_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_find_my_disable passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_find_my_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_find_my_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_find_my_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_find_my_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_find_my_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_find_my_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_find_my_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_find_my_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_find_my_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_firewall_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_firewall_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_firewall_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_firewall_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_firewall_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_firewall_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_gatekeeper_identified_developers_allowed -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-14
# * SI-7(1), SI-7(15)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/sbin/spctl --status --verbose | /usr/bin/grep -c "developer id enabled"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_gatekeeper_identified_developers_allowed'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_gatekeeper_identified_developers_allowed'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_gatekeeper_identified_developers_allowed" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_gatekeeper_identified_developers_allowed passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_gatekeeper_identified_developers_allowed -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_gatekeeper_identified_developers_allowed" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_gatekeeper_identified_developers_allowed -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_gatekeeper_identified_developers_allowed passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_gatekeeper_identified_developers_allowed failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_gatekeeper_identified_developers_allowed -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_gatekeeper_identified_developers_allowed" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_gatekeeper_identified_developers_allowed -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_gatekeeper_identified_developers_allowed failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_gatekeeper_identified_developers_allowed failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_gatekeeper_identified_developers_allowed -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_gatekeeper_identified_developers_allowed" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_gatekeeper_identified_developers_allowed -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_gatekeeper_identified_developers_allowed failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_gatekeeper_identified_developers_allowed does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_gatekeeper_identified_developers_allowed -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_guest_account_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_guest_account_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_guest_account_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_guest_account_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_account_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_guest_account_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_account_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_guest_account_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_hot_corners_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles -P -o stdout | /usr/bin/grep -Ec '"wvous-bl-corner" = 0|"wvous-br-corner" = 0|"wvous-tl-corner" = 0|"wvous-tr-corner" = 0'
)
    # expected result {'integer': 4}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_hot_corners_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_hot_corners_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_hot_corners_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "4" ]]; then
        logmessage "system_settings_hot_corners_disable passed (Result: $result_value, Expected: \"{'integer': 4}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_hot_corners_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_hot_corners_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_hot_corners_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_hot_corners_disable passed (Result: $result_value, Expected: "{'integer': 4}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_hot_corners_disable failed (Result: $result_value, Expected: \"{'integer': 4}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_hot_corners_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_hot_corners_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_hot_corners_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_hot_corners_disable failed (Result: $result_value, Expected: "{'integer': 4}")"
        else
            logmessage "system_settings_hot_corners_disable failed (Result: $result_value, Expected: \"{'integer': 4}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_hot_corners_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_hot_corners_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_hot_corners_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_hot_corners_disable failed (Result: $result_value, Expected: "{'integer': 4}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_hot_corners_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_hot_corners_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_improve_siri_dictation_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.assistant.support')\
.objectForKey('Siri Data Sharing Opt-In Status').js
EOS
)
    # expected result {'integer': 2}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_improve_siri_dictation_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_improve_siri_dictation_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_improve_siri_dictation_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "2" ]]; then
        logmessage "system_settings_improve_siri_dictation_disable passed (Result: $result_value, Expected: \"{'integer': 2}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_improve_siri_dictation_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_improve_siri_dictation_disable passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_improve_siri_dictation_disable failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_improve_siri_dictation_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_improve_siri_dictation_disable failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "system_settings_improve_siri_dictation_disable failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_improve_siri_dictation_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_improve_siri_dictation_disable failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_improve_siri_dictation_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_internet_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_internet_sharing_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_internet_sharing_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_internet_sharing_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_internet_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_internet_sharing_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_internet_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_internet_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_location_services_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/sudo -u _locationd /usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.locationd')\
.objectForKey('LocationServicesEnabled').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_location_services_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_location_services_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_location_services_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "system_settings_location_services_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_location_services_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_location_services_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_location_services_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_location_services_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_location_services_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_location_services_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_location_services_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_location_services_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_location_services_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_location_services_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_location_services_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_location_services_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_location_services_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_location_services_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_location_services_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_location_services_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_loginwindow_prompt_username_password_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_loginwindow_prompt_username_password_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_loginwindow_prompt_username_password_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_loginwindow_prompt_username_password_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_loginwindow_prompt_username_password_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_loginwindow_prompt_username_password_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_media_sharing_disabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
function run() {
  let pref1 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.preferences.sharing.SharingPrefsExtension')\
  .objectForKey('homeSharingUIStatus'))
  let pref2 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.preferences.sharing.SharingPrefsExtension')\
  .objectForKey('legacySharingUIStatus'))
  let pref3 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.preferences.sharing.SharingPrefsExtension')\
  .objectForKey('mediaSharingUIStatus'))
  if ( pref1 == 0 && pref2 == 0 && pref3 == 0 ) {
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_media_sharing_disabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_media_sharing_disabled'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_media_sharing_disabled" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_media_sharing_disabled passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_media_sharing_disabled" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_media_sharing_disabled passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_media_sharing_disabled failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_media_sharing_disabled" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_media_sharing_disabled failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_media_sharing_disabled failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_media_sharing_disabled" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_media_sharing_disabled failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_media_sharing_disabled does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_password_hints_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_password_hints_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_password_hints_disable passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_password_hints_disable failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_password_hints_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_password_hints_disable failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "system_settings_password_hints_disable failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_password_hints_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_password_hints_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_password_hints_disable failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_personalized_advertising_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_personalized_advertising_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_personalized_advertising_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_personalized_advertising_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_personalized_advertising_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_printer_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_printer_sharing_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_printer_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_printer_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_printer_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_printer_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 1}")"
        else
            logmessage "system_settings_printer_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_printer_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_printer_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_printer_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_rae_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_rae_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_rae_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_rae_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_rae_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_rae_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_rae_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_remote_management_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_remote_management_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_remote_management_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_remote_management_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_remote_management_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_remote_management_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_remote_management_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_remote_management_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_remote_management_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_remote_management_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_screen_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_screen_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screen_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_screen_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screen_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screensaver_ask_for_password_delay_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screensaver_ask_for_password_delay_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_screensaver_ask_for_password_delay_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_ask_for_password_delay_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_ask_for_password_delay_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_screensaver_ask_for_password_delay_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_screensaver_ask_for_password_delay_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_screensaver_ask_for_password_delay_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_screensaver_password_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11
# * IA-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.screensaver')\
.objectForKey('askForPassword').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screensaver_password_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screensaver_password_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_screensaver_password_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_screensaver_password_enforce passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_screensaver_password_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_screensaver_password_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_password_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_screensaver_password_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_screensaver_password_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_password_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_password_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_screensaver_password_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_screensaver_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_screensaver_password_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_password_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_password_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_screensaver_password_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_screensaver_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_screensaver_password_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_screensaver_password_enforce -dict-add finding -bool NO
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
  if ( timeout <= 900 ) {
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screensaver_timeout_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screensaver_timeout_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_screensaver_timeout_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_screensaver_timeout_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_timeout_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_screensaver_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_screensaver_timeout_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screensaver_timeout_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_screensaver_timeout_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_screensaver_timeout_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_screensaver_timeout_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_siri_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1), CM-7(5)
# * SC-7(10)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowAssistant').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_siri_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_siri_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_siri_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "system_settings_siri_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_siri_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_siri_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_siri_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_siri_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_siri_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_siri_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_siri_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_siri_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_siri_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_siri_settings_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1), CM-7(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles show -output stdout-xml | /usr/bin/xmllint --xpath '//key[text()="DisabledSystemSettings"]/following-sibling::*[1]' - | /usr/bin/grep -c com.apple.Siri-Settings.extension
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_siri_settings_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_siri_settings_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_siri_settings_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_siri_settings_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_siri_settings_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_siri_settings_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_siri_settings_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_siri_settings_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_siri_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_siri_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_siri_settings_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_siri_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_siri_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_siri_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_siri_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_siri_settings_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_siri_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_siri_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_siri_settings_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_siri_settings_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_smbd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_smbd_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_smbd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_smbd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_smbd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_smbd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_smbd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_smbd_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_ssh_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7, CM-7(1)
# * IA-2(8)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/bin/launchctl print-disabled system | /usr/bin/grep -c '"com.openssh.sshd" => enabled'
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_ssh_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_ssh_enable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_ssh_enable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_ssh_enable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_ssh_enable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_ssh_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_ssh_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_ssh_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_ssh_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_ssh_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_ssh_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_ssh_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_ssh_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_system_wide_preferences_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_system_wide_preferences_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_system_wide_preferences_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_system_wide_preferences_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool NO
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
    # expected result {'string': 'time.nist.gov'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_time_server_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_time_server_configure'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_time_server_configure" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "time.nist.gov" ]]; then
        logmessage "system_settings_time_server_configure passed (Result: $result_value, Expected: \"{'string': 'time.nist.gov'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_time_server_configure" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_time_server_configure passed (Result: $result_value, Expected: "{'string': 'time.nist.gov'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_time_server_configure failed (Result: $result_value, Expected: \"{'string': 'time.nist.gov'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_server_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_time_server_configure failed (Result: $result_value, Expected: "{'string': 'time.nist.gov'}")"
        else
            logmessage "system_settings_time_server_configure failed (Result: $result_value, Expected: \"{'string': 'time.nist.gov'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_server_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_time_server_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_time_server_configure failed (Result: $result_value, Expected: "{'string': 'time.nist.gov'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_time_server_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_time_server_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: stig - system_settings_time_server_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_time_server_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_server_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_time_server_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_time_server_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_time_server_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_time_server_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_time_server_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_time_server_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_token_removal_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-11
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security.smartcard')\
.objectForKey('tokenRemovalAction').js
EOS
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_token_removal_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_token_removal_enforce'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_token_removal_enforce" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_token_removal_enforce passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_token_removal_enforce -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_token_removal_enforce" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_token_removal_enforce -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_token_removal_enforce passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_token_removal_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_token_removal_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_token_removal_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_token_removal_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_token_removal_enforce failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_token_removal_enforce failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_token_removal_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_token_removal_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_token_removal_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_token_removal_enforce failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_token_removal_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_token_removal_enforce -dict-add finding -bool NO
fi

#####----- Rule: system_settings_touch_id_settings_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1), CM-7(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles show -output stdout-xml | /usr/bin/xmllint --xpath '//key[text()="DisabledSystemSettings"]/following-sibling::*[1]' - | /usr/bin/grep -c "com.apple.Touch-ID-Settings.extension"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_touch_id_settings_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_touch_id_settings_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_touch_id_settings_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_touch_id_settings_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_touch_id_settings_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_touch_id_settings_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_touch_id_settings_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_touch_id_settings_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_touch_id_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_touch_id_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_touch_id_settings_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_touch_id_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_touch_id_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_touch_id_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_touch_id_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_touch_id_settings_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_touch_id_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_touch_id_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_touch_id_settings_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_touch_id_settings_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_touchid_unlock_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowFingerprintForUnlock').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_touchid_unlock_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_touchid_unlock_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_touchid_unlock_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "system_settings_touchid_unlock_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_touchid_unlock_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_touchid_unlock_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_touchid_unlock_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_touchid_unlock_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_touchid_unlock_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_touchid_unlock_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_touchid_unlock_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_touchid_unlock_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_touchid_unlock_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_touchid_unlock_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_touchid_unlock_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_touchid_unlock_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_touchid_unlock_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_touchid_unlock_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_touchid_unlock_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_touchid_unlock_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_usb_restricted_mode -----#####
## Addresses the following NIST 800-53 controls: 
# * MP-7
# * SC-41
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
  function run() {
    let pref1 = ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
  .objectForKey('allowUSBRestrictedMode'))
    if ( pref1 == false ) {
      return("false")
    } else {
      return("true")
    }
  }
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_usb_restricted_mode'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_usb_restricted_mode'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_usb_restricted_mode" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "system_settings_usb_restricted_mode passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_usb_restricted_mode -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_usb_restricted_mode" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_usb_restricted_mode -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_usb_restricted_mode passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_usb_restricted_mode failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_usb_restricted_mode -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_usb_restricted_mode" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_usb_restricted_mode -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_usb_restricted_mode failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_usb_restricted_mode failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_usb_restricted_mode -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_usb_restricted_mode" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_usb_restricted_mode -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_usb_restricted_mode failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_usb_restricted_mode does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_usb_restricted_mode -dict-add finding -bool NO
fi

#####----- Rule: system_settings_wallet_applepay_settings_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1), CM-7(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles show -output stdout-xml | /usr/bin/xmllint --xpath '//key[text()="DisabledSystemSettings"]/following-sibling::*[1]' - | /usr/bin/grep -c "com.apple.WalletSettingsExtension"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_wallet_applepay_settings_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_wallet_applepay_settings_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_wallet_applepay_settings_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_wallet_applepay_settings_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_wallet_applepay_settings_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_wallet_applepay_settings_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_wallet_applepay_settings_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: stig - system_settings_wallet_applepay_settings_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_wallet_applepay_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_wallet_applepay_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_wallet_applepay_settings_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_wallet_applepay_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_wallet_applepay_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_wallet_applepay_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_wallet_applepay_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_wallet_applepay_settings_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_wallet_applepay_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: stig - system_settings_wallet_applepay_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_wallet_applepay_settings_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_wallet_applepay_settings_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_acls_files_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_acls_files_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_acls_folders_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_acls_folders_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_auditd_enabled'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_auditd_enabled'))["exempt_reason"]
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
    
#####----- Rule: audit_configure_capacity_notify -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-5(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_configure_capacity_notify'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_configure_capacity_notify'))["exempt_reason"]
EOS
)

audit_configure_capacity_notify_audit_score=$($plb -c "print audit_configure_capacity_notify:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_configure_capacity_notify_audit_score == "true" ]]; then
        ask 'audit_configure_capacity_notify - Run the command(s)-> /usr/bin/sed -i.bak '"'"'s/.*minfree.*/minfree:25/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_configure_capacity_notify ..."
            /usr/bin/sed -i.bak 's/.*minfree.*/minfree:25/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_configure_capacity_notify already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_configure_capacity_notify has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_control_acls_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_acls_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_acls_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_group_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_mode_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_control_owner_configure'))["exempt_reason"]
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
    
#####----- Rule: audit_failure_halt -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-5

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_failure_halt'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_failure_halt'))["exempt_reason"]
EOS
)

audit_failure_halt_audit_score=$($plb -c "print audit_failure_halt:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_failure_halt_audit_score == "true" ]]; then
        ask 'audit_failure_halt - Run the command(s)-> /usr/bin/sed -i.bak '"'"'s/^policy.*/policy: ahlt,argv/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_failure_halt ..."
            /usr/bin/sed -i.bak 's/^policy.*/policy: ahlt,argv/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_failure_halt already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_failure_halt has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_files_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_group_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_mode_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_files_owner_configure'))["exempt_reason"]
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
    
#####----- Rule: audit_flags_aa_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_aa_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_aa_configure'))["exempt_reason"]
EOS
)

audit_flags_aa_configure_audit_score=$($plb -c "print audit_flags_aa_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_aa_configure_audit_score == "true" ]]; then
        ask 'audit_flags_aa_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*[^-]aa" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,aa/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_flags_aa_configure ..."
            /usr/bin/grep -qE "^flags.*[^-]aa" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,aa/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_flags_aa_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_flags_aa_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_flags_ad_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12), AC-2(4)
# * AC-6(9)
# * AU-12
# * AU-2
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_ad_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_ad_configure'))["exempt_reason"]
EOS
)

audit_flags_ad_configure_audit_score=$($plb -c "print audit_flags_ad_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_ad_configure_audit_score == "true" ]]; then
        ask 'audit_flags_ad_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*[^-]ad" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,ad/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_flags_ad_configure ..."
            /usr/bin/grep -qE "^flags.*[^-]ad" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,ad/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_flags_ad_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_flags_ad_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_flags_ex_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * CM-5(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_ex_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_ex_configure'))["exempt_reason"]
EOS
)

audit_flags_ex_configure_audit_score=$($plb -c "print audit_flags_ex_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_ex_configure_audit_score == "true" ]]; then
        ask 'audit_flags_ex_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*-ex" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,-ex/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_flags_ex_configure ..."
            /usr/bin/grep -qE "^flags.*-ex" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,-ex/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_flags_ex_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_flags_ex_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_flags_fd_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fd_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fd_configure'))["exempt_reason"]
EOS
)

audit_flags_fd_configure_audit_score=$($plb -c "print audit_flags_fd_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_fd_configure_audit_score == "true" ]]; then
        ask 'audit_flags_fd_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*-fd" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,-fd/'"'"' /etc/security/audit_control;/usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_flags_fd_configure ..."
            /usr/bin/grep -qE "^flags.*-fd" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,-fd/' /etc/security/audit_control;/usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_flags_fd_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_flags_fd_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_flags_fm_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fm_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fm_configure'))["exempt_reason"]
EOS
)

audit_flags_fm_configure_audit_score=$($plb -c "print audit_flags_fm_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_fm_configure_audit_score == "true" ]]; then
        ask 'audit_flags_fm_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*fm" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,fm/'"'"' /etc/security/audit_control;/usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_flags_fm_configure ..."
            /usr/bin/grep -qE "^flags.*fm" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,fm/' /etc/security/audit_control;/usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_flags_fm_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_flags_fm_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_flags_fr_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fr_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fr_configure'))["exempt_reason"]
EOS
)

audit_flags_fr_configure_audit_score=$($plb -c "print audit_flags_fr_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_fr_configure_audit_score == "true" ]]; then
        ask 'audit_flags_fr_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*-fr" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,-fr/'"'"' /etc/security/audit_control;/usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_flags_fr_configure ..."
            /usr/bin/grep -qE "^flags.*-fr" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,-fr/' /etc/security/audit_control;/usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_flags_fr_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_flags_fr_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_flags_fw_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(12)
# * AU-12
# * AU-2
# * AU-9
# * CM-5(1)
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fw_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_fw_configure'))["exempt_reason"]
EOS
)

audit_flags_fw_configure_audit_score=$($plb -c "print audit_flags_fw_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_fw_configure_audit_score == "true" ]]; then
        ask 'audit_flags_fw_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*-fw" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,-fw/'"'"' /etc/security/audit_control;/usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_flags_fw_configure ..."
            /usr/bin/grep -qE "^flags.*-fw" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,-fw/' /etc/security/audit_control;/usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_flags_fw_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_flags_fw_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_flags_lo_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17(1)
# * AC-2(12)
# * AU-12
# * AU-2
# * MA-4(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_lo_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_flags_lo_configure'))["exempt_reason"]
EOS
)

audit_flags_lo_configure_audit_score=$($plb -c "print audit_flags_lo_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_flags_lo_configure_audit_score == "true" ]]; then
        ask 'audit_flags_lo_configure - Run the command(s)-> /usr/bin/grep -qE "^flags.*[^-]lo" /etc/security/audit_control || /usr/bin/sed -i.bak '"'"'/^flags/ s/$/,lo/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_flags_lo_configure ..."
            /usr/bin/grep -qE "^flags.*[^-]lo" /etc/security/audit_control || /usr/bin/sed -i.bak '/^flags/ s/$/,lo/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_flags_lo_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_flags_lo_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_folder_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-9

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folder_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folder_group_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folder_owner_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folder_owner_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folders_mode_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_folders_mode_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_retention_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_retention_configure'))["exempt_reason"]
EOS
)

audit_retention_configure_audit_score=$($plb -c "print audit_retention_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_retention_configure_audit_score == "true" ]]; then
        ask 'audit_retention_configure - Run the command(s)-> /usr/bin/sed -i.bak '"'"'s/^expire-after.*/expire-after:7d/'"'"' /etc/security/audit_control; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_retention_configure ..."
            /usr/bin/sed -i.bak 's/^expire-after.*/expire-after:7d/' /etc/security/audit_control; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_retention_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_retention_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: audit_settings_failure_notify -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-5, AU-5(2)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_settings_failure_notify'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('audit_settings_failure_notify'))["exempt_reason"]
EOS
)

audit_settings_failure_notify_audit_score=$($plb -c "print audit_settings_failure_notify:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $audit_settings_failure_notify_audit_score == "true" ]]; then
        ask 'audit_settings_failure_notify - Run the command(s)-> /usr/bin/sed -i.bak '"'"'s/logger -p/logger -s -p/'"'"' /etc/security/audit_warn; /usr/sbin/audit -s ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: audit_settings_failure_notify ..."
            /usr/bin/sed -i.bak 's/logger -p/logger -s -p/' /etc/security/audit_warn; /usr/sbin/audit -s
        fi
    else
        logmessage "Settings for: audit_settings_failure_notify already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "audit_settings_failure_notify has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: auth_pam_login_smartcard_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(1), IA-2(2), IA-2(8)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_login_smartcard_enforce'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_login_smartcard_enforce'))["exempt_reason"]
EOS
)

auth_pam_login_smartcard_enforce_audit_score=$($plb -c "print auth_pam_login_smartcard_enforce:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $auth_pam_login_smartcard_enforce_audit_score == "true" ]]; then
        ask 'auth_pam_login_smartcard_enforce - Run the command(s)-> /bin/cat > /etc/pam.d/login << LOGIN_END
# login: auth account password session
auth        sufficient    pam_smartcard.so
auth        optional      pam_krb5.so use_kcminit
auth        optional      pam_ntlm.so try_first_pass
auth        optional      pam_mount.so try_first_pass
auth        required      pam_opendirectory.so try_first_pass
auth        required      pam_deny.so
account     required      pam_nologin.so
account     required      pam_opendirectory.so
password    required      pam_opendirectory.so
session     required      pam_launchd.so
session     required      pam_uwtmp.so
session     optional      pam_mount.so
LOGIN_END


/bin/chmod 644 /etc/pam.d/login
/usr/sbin/chown root:wheel /etc/pam.d/login ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: auth_pam_login_smartcard_enforce ..."
            /bin/cat > /etc/pam.d/login << LOGIN_END
# login: auth account password session
auth        sufficient    pam_smartcard.so
auth        optional      pam_krb5.so use_kcminit
auth        optional      pam_ntlm.so try_first_pass
auth        optional      pam_mount.so try_first_pass
auth        required      pam_opendirectory.so try_first_pass
auth        required      pam_deny.so
account     required      pam_nologin.so
account     required      pam_opendirectory.so
password    required      pam_opendirectory.so
session     required      pam_launchd.so
session     required      pam_uwtmp.so
session     optional      pam_mount.so
LOGIN_END


/bin/chmod 644 /etc/pam.d/login
/usr/sbin/chown root:wheel /etc/pam.d/login
        fi
    else
        logmessage "Settings for: auth_pam_login_smartcard_enforce already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "auth_pam_login_smartcard_enforce has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: auth_pam_su_smartcard_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(1), IA-2(2), IA-2(8)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_su_smartcard_enforce'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_su_smartcard_enforce'))["exempt_reason"]
EOS
)

auth_pam_su_smartcard_enforce_audit_score=$($plb -c "print auth_pam_su_smartcard_enforce:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $auth_pam_su_smartcard_enforce_audit_score == "true" ]]; then
        ask 'auth_pam_su_smartcard_enforce - Run the command(s)-> /bin/cat > /etc/pam.d/su << SU_END
# su: auth account password session
auth        sufficient    pam_smartcard.so
auth        required      pam_rootok.so
auth        required      pam_group.so no_warn group=admin,wheel ruser root_only fail_safe
account     required      pam_permit.so
account     required      pam_opendirectory.so no_check_shell
password    required      pam_opendirectory.so
session     required      pam_launchd.so
SU_END

# Fix new file ownership and permissions
/bin/chmod 644 /etc/pam.d/su
/usr/sbin/chown root:wheel /etc/pam.d/su ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: auth_pam_su_smartcard_enforce ..."
            /bin/cat > /etc/pam.d/su << SU_END
# su: auth account password session
auth        sufficient    pam_smartcard.so
auth        required      pam_rootok.so
auth        required      pam_group.so no_warn group=admin,wheel ruser root_only fail_safe
account     required      pam_permit.so
account     required      pam_opendirectory.so no_check_shell
password    required      pam_opendirectory.so
session     required      pam_launchd.so
SU_END

# Fix new file ownership and permissions
/bin/chmod 644 /etc/pam.d/su
/usr/sbin/chown root:wheel /etc/pam.d/su
        fi
    else
        logmessage "Settings for: auth_pam_su_smartcard_enforce already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "auth_pam_su_smartcard_enforce has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: auth_pam_sudo_smartcard_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(1), IA-2(2), IA-2(8)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_sudo_smartcard_enforce'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_pam_sudo_smartcard_enforce'))["exempt_reason"]
EOS
)

auth_pam_sudo_smartcard_enforce_audit_score=$($plb -c "print auth_pam_sudo_smartcard_enforce:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $auth_pam_sudo_smartcard_enforce_audit_score == "true" ]]; then
        ask 'auth_pam_sudo_smartcard_enforce - Run the command(s)-> /bin/cat > /etc/pam.d/sudo << SUDO_END
# sudo: auth account password session
auth        sufficient    pam_smartcard.so
auth        required      pam_opendirectory.so
auth        required      pam_deny.so
account     required      pam_permit.so
password    required      pam_deny.so
session     required      pam_permit.so
SUDO_END

/bin/chmod 444 /etc/pam.d/sudo
/usr/sbin/chown root:wheel /etc/pam.d/sudo ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: auth_pam_sudo_smartcard_enforce ..."
            /bin/cat > /etc/pam.d/sudo << SUDO_END
# sudo: auth account password session
auth        sufficient    pam_smartcard.so
auth        required      pam_opendirectory.so
auth        required      pam_deny.so
account     required      pam_permit.so
password    required      pam_deny.so
session     required      pam_permit.so
SUDO_END

/bin/chmod 444 /etc/pam.d/sudo
/usr/sbin/chown root:wheel /etc/pam.d/sudo
        fi
    else
        logmessage "Settings for: auth_pam_sudo_smartcard_enforce already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "auth_pam_sudo_smartcard_enforce has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: auth_ssh_password_authentication_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(1), IA-2(2), IA-2(6), IA-2(8)
# * IA-5(2)
# * MA-4

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_ssh_password_authentication_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('auth_ssh_password_authentication_disable'))["exempt_reason"]
EOS
)

auth_ssh_password_authentication_disable_audit_score=$($plb -c "print auth_ssh_password_authentication_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $auth_ssh_password_authentication_disable_audit_score == "true" ]]; then
        ask 'auth_ssh_password_authentication_disable - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')
if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi
echo "passwordauthentication no" >> "${include_dir}01-mscp-sshd.conf"
echo "kbdinteractiveauthentication no" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: auth_ssh_password_authentication_disable ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')
if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi
echo "passwordauthentication no" >> "${include_dir}01-mscp-sshd.conf"
echo "kbdinteractiveauthentication no" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: auth_ssh_password_authentication_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "auth_ssh_password_authentication_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_asl_log_files_owner_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-11

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_asl_log_files_owner_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_asl_log_files_owner_group_configure'))["exempt_reason"]
EOS
)

os_asl_log_files_owner_group_configure_audit_score=$($plb -c "print os_asl_log_files_owner_group_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_asl_log_files_owner_group_configure_audit_score == "true" ]]; then
        ask 'os_asl_log_files_owner_group_configure - Run the command(s)-> /usr/sbin/chown root:wheel $(/usr/bin/stat -f '"'"'%%Su:%%Sg:%%N'"'"' $(/usr/bin/grep -e '"'"'^>'"'"' /etc/asl.conf /etc/asl/* | /usr/bin/awk '"'"'{ print $2 }'"'"') 2> /dev/null | /usr/bin/awk '"'"'!/^root:wheel:/{print $1}'"'"' | /usr/bin/awk -F":" '"'"'!/^root:wheel:/{print $3}'"'"') ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_asl_log_files_owner_group_configure ..."
            /usr/sbin/chown root:wheel $(/usr/bin/stat -f '%Su:%Sg:%N' $(/usr/bin/grep -e '^>' /etc/asl.conf /etc/asl/* | /usr/bin/awk '{ print $2 }') 2> /dev/null | /usr/bin/awk '!/^root:wheel:/{print $1}' | /usr/bin/awk -F":" '!/^root:wheel:/{print $3}')
        fi
    else
        logmessage "Settings for: os_asl_log_files_owner_group_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_asl_log_files_owner_group_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_asl_log_files_permissions_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-11

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_asl_log_files_permissions_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_asl_log_files_permissions_configure'))["exempt_reason"]
EOS
)

os_asl_log_files_permissions_configure_audit_score=$($plb -c "print os_asl_log_files_permissions_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_asl_log_files_permissions_configure_audit_score == "true" ]]; then
        ask 'os_asl_log_files_permissions_configure - Run the command(s)-> /bin/chmod 640 $(/usr/bin/stat -f '"'"'%%A:%%N'"'"' $(/usr/bin/grep -e '"'"'^>'"'"' /etc/asl.conf /etc/asl/* | /usr/bin/awk '"'"'{ print $2 }'"'"') 2> /dev/null | /usr/bin/awk -F":" '"'"'!/640/{print $2}'"'"') ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_asl_log_files_permissions_configure ..."
            /bin/chmod 640 $(/usr/bin/stat -f '%A:%N' $(/usr/bin/grep -e '^>' /etc/asl.conf /etc/asl/* | /usr/bin/awk '{ print $2 }') 2> /dev/null | /usr/bin/awk -F":" '!/640/{print $2}')
        fi
    else
        logmessage "Settings for: os_asl_log_files_permissions_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_asl_log_files_permissions_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_authenticated_root_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_authenticated_root_enable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_gatekeeper_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_gatekeeper_enable'))["exempt_reason"]
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
    
#####----- Rule: os_home_folders_secure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_home_folders_secure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_home_folders_secure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_httpd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_httpd_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_install_log_retention_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_install_log_retention_configure'))["exempt_reason"]
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
    
#####----- Rule: os_newsyslog_files_owner_group_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-11

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_newsyslog_files_owner_group_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_newsyslog_files_owner_group_configure'))["exempt_reason"]
EOS
)

os_newsyslog_files_owner_group_configure_audit_score=$($plb -c "print os_newsyslog_files_owner_group_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_newsyslog_files_owner_group_configure_audit_score == "true" ]]; then
        ask 'os_newsyslog_files_owner_group_configure - Run the command(s)-> /usr/sbin/chown root:wheel $(/usr/bin/stat -f '"'"'%%Su:%%Sg:%%N'"'"' $(/usr/bin/grep -v '"'"'^#'"'"' /etc/newsyslog.conf | /usr/bin/awk '"'"'{ print $1 }'"'"') 2> /dev/null | /usr/bin/awk -F":" '"'"'!/^root:wheel:/{print $3}'"'"') ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_newsyslog_files_owner_group_configure ..."
            /usr/sbin/chown root:wheel $(/usr/bin/stat -f '%Su:%Sg:%N' $(/usr/bin/grep -v '^#' /etc/newsyslog.conf | /usr/bin/awk '{ print $1 }') 2> /dev/null | /usr/bin/awk -F":" '!/^root:wheel:/{print $3}')
        fi
    else
        logmessage "Settings for: os_newsyslog_files_owner_group_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_newsyslog_files_owner_group_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_newsyslog_files_permissions_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-11

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_newsyslog_files_permissions_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_newsyslog_files_permissions_configure'))["exempt_reason"]
EOS
)

os_newsyslog_files_permissions_configure_audit_score=$($plb -c "print os_newsyslog_files_permissions_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_newsyslog_files_permissions_configure_audit_score == "true" ]]; then
        ask 'os_newsyslog_files_permissions_configure - Run the command(s)-> /bin/chmod 640 $(/usr/bin/stat -f '"'"'%%A:%%N'"'"' $(/usr/bin/grep -v '"'"'^#'"'"' /etc/newsyslog.conf | /usr/bin/awk '"'"'{ print $1 }'"'"') 2> /dev/null | /usr/bin/awk '"'"'!/640/{print $1}'"'"' | awk -F":" '"'"'!/640/{print $2}'"'"') ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_newsyslog_files_permissions_configure ..."
            /bin/chmod 640 $(/usr/bin/stat -f '%A:%N' $(/usr/bin/grep -v '^#' /etc/newsyslog.conf | /usr/bin/awk '{ print $1 }') 2> /dev/null | /usr/bin/awk '!/640/{print $1}' | awk -F":" '!/640/{print $2}')
        fi
    else
        logmessage "Settings for: os_newsyslog_files_permissions_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_newsyslog_files_permissions_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_nfsd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_nfsd_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_password_hint_remove'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_password_hint_remove'))["exempt_reason"]
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
    
#####----- Rule: os_policy_banner_loginwindow_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-8

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_loginwindow_enforce'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_loginwindow_enforce'))["exempt_reason"]
EOS
)

os_policy_banner_loginwindow_enforce_audit_score=$($plb -c "print os_policy_banner_loginwindow_enforce:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_policy_banner_loginwindow_enforce_audit_score == "true" ]]; then
        ask 'os_policy_banner_loginwindow_enforce - Run the command(s)-> bannerText="You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS (which includes any device attached to this IS), you consent to the following conditions:

-The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations and defense, personnel misconduct (PM), law enforcement (LE), and counterintelligence (CI) investigations.

-At any time, the USG may inspect and seize data stored on this IS.

-Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG authorized purpose.

-This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy.

-Notwithstanding the above, using this IS does not constitute consent to PM, LE or CI investigative searching or monitoring of the content of privileged communications, or work product, related to personal representation or services by attorneys, psychotherapists, or clergy, and their assistants. Such communications and work product are private and confidential. See User Agreement for details."
/bin/mkdir /Library/Security/PolicyBanner.rtfd
/usr/bin/textutil -convert rtf -output /Library/Security/PolicyBanner.rtfd/TXT.rtf -stdin <<EOF
$bannerText
EOF ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_policy_banner_loginwindow_enforce ..."
            bannerText="You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS (which includes any device attached to this IS), you consent to the following conditions:

-The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations and defense, personnel misconduct (PM), law enforcement (LE), and counterintelligence (CI) investigations.

-At any time, the USG may inspect and seize data stored on this IS.

-Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG authorized purpose.

-This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy.

-Notwithstanding the above, using this IS does not constitute consent to PM, LE or CI investigative searching or monitoring of the content of privileged communications, or work product, related to personal representation or services by attorneys, psychotherapists, or clergy, and their assistants. Such communications and work product are private and confidential. See User Agreement for details."
/bin/mkdir /Library/Security/PolicyBanner.rtfd
/usr/bin/textutil -convert rtf -output /Library/Security/PolicyBanner.rtfd/TXT.rtf -stdin <<EOF
$bannerText
EOF
        fi
    else
        logmessage "Settings for: os_policy_banner_loginwindow_enforce already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_policy_banner_loginwindow_enforce has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_policy_banner_ssh_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-8

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_ssh_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_ssh_configure'))["exempt_reason"]
EOS
)

os_policy_banner_ssh_configure_audit_score=$($plb -c "print os_policy_banner_ssh_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_policy_banner_ssh_configure_audit_score == "true" ]]; then
        ask 'os_policy_banner_ssh_configure - Run the command(s)-> bannerText="You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only.

By using this IS (which includes any device attached to this IS), you consent to the following conditions:

-The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations and defense, personnel misconduct (PM), law enforcement (LE), and counterintelligence (CI) investigations.

-At any time, the USG may inspect and seize data stored on this IS.

-Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose.

-This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy.

-Notwithstanding the above, using this IS does not constitute consent to PM, LE or CI investigative searching or monitoring of the content of privileged communications, or work product, related to personal representation or services by attorneys, psychotherapists, or clergy, and their assistants. Such communications and work product are private and confidential. See User Agreement for details."
/bin/echo "${bannerText}" > /etc/banner ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_policy_banner_ssh_configure ..."
            bannerText="You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only.

By using this IS (which includes any device attached to this IS), you consent to the following conditions:

-The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations and defense, personnel misconduct (PM), law enforcement (LE), and counterintelligence (CI) investigations.

-At any time, the USG may inspect and seize data stored on this IS.

-Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose.

-This IS includes security measures (e.g., authentication and access controls) to protect USG interests--not for your personal benefit or privacy.

-Notwithstanding the above, using this IS does not constitute consent to PM, LE or CI investigative searching or monitoring of the content of privileged communications, or work product, related to personal representation or services by attorneys, psychotherapists, or clergy, and their assistants. Such communications and work product are private and confidential. See User Agreement for details."
/bin/echo "${bannerText}" > /etc/banner
        fi
    else
        logmessage "Settings for: os_policy_banner_ssh_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_policy_banner_ssh_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_policy_banner_ssh_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-8

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_ssh_enforce'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_policy_banner_ssh_enforce'))["exempt_reason"]
EOS
)

os_policy_banner_ssh_enforce_audit_score=$($plb -c "print os_policy_banner_ssh_enforce:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_policy_banner_ssh_enforce_audit_score == "true" ]]; then
        ask 'os_policy_banner_ssh_enforce - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF '"'"'banner /etc/banner'"'"' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "banner /etc/banner" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_policy_banner_ssh_enforce ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF 'banner /etc/banner' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "banner /etc/banner" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: os_policy_banner_ssh_enforce already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_policy_banner_ssh_enforce has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_root_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_root_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_root_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sip_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sip_enable'))["exempt_reason"]
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
    
#####----- Rule: os_ssh_fips_compliant -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17(2)
# * IA-7
# * SC-13
# * SC-8(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_fips_compliant'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_fips_compliant'))["exempt_reason"]
EOS
)

os_ssh_fips_compliant_audit_score=$($plb -c "print os_ssh_fips_compliant:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_ssh_fips_compliant_audit_score == "true" ]]; then
        ask 'os_ssh_fips_compliant - Run the command(s)-> fips_ssh_config="Host *
Ciphers aes128-gcm@openssh.com
HostbasedAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
KexAlgorithms ecdh-sha2-nistp256
MACs hmac-sha2-256
PubkeyAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
CASignatureAlgorithms ecdsa-sha2-nistp256"
/bin/echo "${fips_ssh_config}" > /etc/ssh/ssh_config.d/fips_ssh_config ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_ssh_fips_compliant ..."
            fips_ssh_config="Host *
Ciphers aes128-gcm@openssh.com
HostbasedAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
KexAlgorithms ecdh-sha2-nistp256
MACs hmac-sha2-256
PubkeyAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com
CASignatureAlgorithms ecdsa-sha2-nistp256"
/bin/echo "${fips_ssh_config}" > /etc/ssh/ssh_config.d/fips_ssh_config
        fi
    else
        logmessage "Settings for: os_ssh_fips_compliant already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_ssh_fips_compliant has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_ssh_server_alive_count_max_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SC-10

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_server_alive_count_max_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_server_alive_count_max_configure'))["exempt_reason"]
EOS
)

os_ssh_server_alive_count_max_configure_audit_score=$($plb -c "print os_ssh_server_alive_count_max_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_ssh_server_alive_count_max_configure_audit_score == "true" ]]; then
        ask 'os_ssh_server_alive_count_max_configure - Run the command(s)-> for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '"'"'$2 > 500 {print $1}'"'"'); do
  config=$(/usr/bin/sudo -u $u /usr/bin/ssh -Gv . 2>&1 | /usr/bin/awk '"'"'/Reading configuration data/ {print $NF}'"'"'| /usr/bin/tr -d '"'"'\r'"'"')
  configarray=( ${(f)config} )
  for c in $configarray; do
    /usr/bin/sudo -u $u /usr/bin/grep -q '"'"'^ServerAliveCountMax'"'"' "$c" && /usr/bin/sed -i '"'"''"'"' '"'"'s/.*ServerAliveCountMax.*/ServerAliveCountMax 0/'"'"' "$c" || /bin/echo '"'"'ServerAliveCountMax 0'"'"' >> "$c"
  done
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_ssh_server_alive_count_max_configure ..."
            for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 > 500 {print $1}'); do
  config=$(/usr/bin/sudo -u $u /usr/bin/ssh -Gv . 2>&1 | /usr/bin/awk '/Reading configuration data/ {print $NF}'| /usr/bin/tr -d '\r')
  configarray=( ${(f)config} )
  for c in $configarray; do
    /usr/bin/sudo -u $u /usr/bin/grep -q '^ServerAliveCountMax' "$c" && /usr/bin/sed -i '' 's/.*ServerAliveCountMax.*/ServerAliveCountMax 0/' "$c" || /bin/echo 'ServerAliveCountMax 0' >> "$c"
  done
done
        fi
    else
        logmessage "Settings for: os_ssh_server_alive_count_max_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_ssh_server_alive_count_max_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_ssh_server_alive_interval_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * SC-10

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_server_alive_interval_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_ssh_server_alive_interval_configure'))["exempt_reason"]
EOS
)

os_ssh_server_alive_interval_configure_audit_score=$($plb -c "print os_ssh_server_alive_interval_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_ssh_server_alive_interval_configure_audit_score == "true" ]]; then
        ask 'os_ssh_server_alive_interval_configure - Run the command(s)-> for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '"'"'$2 > 500 {print $1}'"'"'); do
  config=$(/usr/bin/sudo -u $u /usr/bin/ssh -Gv . 2>&1 | /usr/bin/awk '"'"'/Reading configuration data/ {print $NF}'"'"'| /usr/bin/tr -d '"'"'\r'"'"')
  configarray=( ${(f)config} )
  for c in $configarray; do
    /usr/bin/sudo -u $u /usr/bin/grep -q '"'"'^ServerAliveInterval'"'"' "$c" && /usr/bin/sed -i '"'"''"'"' '"'"'s/.*ServerAliveInterval.*/ServerAliveInterval 900/'"'"' "$c" || /bin/echo '"'"'ServerAliveInterval 900'"'"' >> "$c"
  done
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_ssh_server_alive_interval_configure ..."
            for u in $(/usr/bin/dscl . -list /Users UniqueID | /usr/bin/awk '$2 > 500 {print $1}'); do
  config=$(/usr/bin/sudo -u $u /usr/bin/ssh -Gv . 2>&1 | /usr/bin/awk '/Reading configuration data/ {print $NF}'| /usr/bin/tr -d '\r')
  configarray=( ${(f)config} )
  for c in $configarray; do
    /usr/bin/sudo -u $u /usr/bin/grep -q '^ServerAliveInterval' "$c" && /usr/bin/sed -i '' 's/.*ServerAliveInterval.*/ServerAliveInterval 900/' "$c" || /bin/echo 'ServerAliveInterval 900' >> "$c"
  done
done
        fi
    else
        logmessage "Settings for: os_ssh_server_alive_interval_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_ssh_server_alive_interval_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sshd_channel_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * SC-10

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_channel_timeout_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_channel_timeout_configure'))["exempt_reason"]
EOS
)

os_sshd_channel_timeout_configure_audit_score=$($plb -c "print os_sshd_channel_timeout_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sshd_channel_timeout_configure_audit_score == "true" ]]; then
        ask 'os_sshd_channel_timeout_configure - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF '"'"'channeltimeout session:*=900'"'"' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "channeltimeout session:*=900" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sshd_channel_timeout_configure ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF 'channeltimeout session:*=900' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "channeltimeout session:*=900" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: os_sshd_channel_timeout_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sshd_channel_timeout_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sshd_client_alive_count_max_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SC-10

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_client_alive_count_max_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_client_alive_count_max_configure'))["exempt_reason"]
EOS
)

os_sshd_client_alive_count_max_configure_audit_score=$($plb -c "print os_sshd_client_alive_count_max_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sshd_client_alive_count_max_configure_audit_score == "true" ]]; then
        ask 'os_sshd_client_alive_count_max_configure - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF '"'"'clientalivecountmax 1'"'"' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "clientalivecountmax 1" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sshd_client_alive_count_max_configure ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF 'clientalivecountmax 1' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "clientalivecountmax 1" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: os_sshd_client_alive_count_max_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sshd_client_alive_count_max_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sshd_client_alive_interval_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * SC-10

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_client_alive_interval_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_client_alive_interval_configure'))["exempt_reason"]
EOS
)

os_sshd_client_alive_interval_configure_audit_score=$($plb -c "print os_sshd_client_alive_interval_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sshd_client_alive_interval_configure_audit_score == "true" ]]; then
        ask 'os_sshd_client_alive_interval_configure - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF '"'"'clientaliveinterval 900'"'"' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "clientaliveinterval 900" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sshd_client_alive_interval_configure ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF 'clientaliveinterval 900' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "clientaliveinterval 900" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: os_sshd_client_alive_interval_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sshd_client_alive_interval_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sshd_fips_compliant -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17(2)
# * IA-7
# * SC-13
# * SC-8(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_fips_compliant'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_fips_compliant'))["exempt_reason"]
EOS
)

os_sshd_fips_compliant_audit_score=$($plb -c "print os_sshd_fips_compliant:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sshd_fips_compliant_audit_score == "true" ]]; then
        ask 'os_sshd_fips_compliant - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

fips_sshd_config=("Ciphers aes128-gcm@openssh.com" "HostbasedAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "KexAlgorithms ecdh-sha2-nistp256" "MACs hmac-sha2-256" "PubkeyAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "CASignatureAlgorithms ecdsa-sha2-nistp256")

for config in $fips_sshd_config; do
  /usr/bin/grep -qxF "$config" "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "$config" >> "${include_dir}01-mscp-sshd.conf"
done

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sshd_fips_compliant ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

fips_sshd_config=("Ciphers aes128-gcm@openssh.com" "HostbasedAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "KexAlgorithms ecdh-sha2-nistp256" "MACs hmac-sha2-256" "PubkeyAcceptedAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp256-cert-v01@openssh.com" "CASignatureAlgorithms ecdsa-sha2-nistp256")

for config in $fips_sshd_config; do
  /usr/bin/grep -qxF "$config" "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "$config" >> "${include_dir}01-mscp-sshd.conf"
done

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: os_sshd_fips_compliant already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sshd_fips_compliant has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sshd_login_grace_time_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * SC-10

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_login_grace_time_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_login_grace_time_configure'))["exempt_reason"]
EOS
)

os_sshd_login_grace_time_configure_audit_score=$($plb -c "print os_sshd_login_grace_time_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sshd_login_grace_time_configure_audit_score == "true" ]]; then
        ask 'os_sshd_login_grace_time_configure - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF '"'"'logingracetime 30'"'"' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "logingracetime 30" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sshd_login_grace_time_configure ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF 'logingracetime 30' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "logingracetime 30" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: os_sshd_login_grace_time_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sshd_login_grace_time_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sshd_permit_root_login_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2(5)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_permit_root_login_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_permit_root_login_configure'))["exempt_reason"]
EOS
)

os_sshd_permit_root_login_configure_audit_score=$($plb -c "print os_sshd_permit_root_login_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sshd_permit_root_login_configure_audit_score == "true" ]]; then
        ask 'os_sshd_permit_root_login_configure - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF '"'"'permitrootlogin no'"'"' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "permitrootlogin no" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sshd_permit_root_login_configure ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF 'permitrootlogin no' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "permitrootlogin no" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: os_sshd_permit_root_login_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sshd_permit_root_login_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sshd_unused_connection_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-12
# * SC-10

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_unused_connection_timeout_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sshd_unused_connection_timeout_configure'))["exempt_reason"]
EOS
)

os_sshd_unused_connection_timeout_configure_audit_score=$($plb -c "print os_sshd_unused_connection_timeout_configure:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_sshd_unused_connection_timeout_configure_audit_score == "true" ]]; then
        ask 'os_sshd_unused_connection_timeout_configure - Run the command(s)-> include_dir=$(/usr/bin/awk '"'"'/^Include/ {print $2}'"'"' /etc/ssh/sshd_config | /usr/bin/tr -d '"'"'*'"'"')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF '"'"'unusedconnectiontimeout 900'"'"' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "unusedconnectiontimeout 900" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_sshd_unused_connection_timeout_configure ..."
            include_dir=$(/usr/bin/awk '/^Include/ {print $2}' /etc/ssh/sshd_config | /usr/bin/tr -d '*')

if [[ -z $include_dir ]]; then
  /usr/bin/sed -i.bk "1s/.*/Include \/etc\/ssh\/sshd_config.d\/\*/" /etc/ssh/sshd_config
fi

/usr/bin/grep -qxF 'unusedconnectiontimeout 900' "${include_dir}01-mscp-sshd.conf" 2>/dev/null || echo "unusedconnectiontimeout 900" >> "${include_dir}01-mscp-sshd.conf"

for file in $(ls ${include_dir}); do
  if [[ "$file" == "100-macos.conf" ]]; then
      continue
  fi
  if [[ "$file" == "01-mscp-sshd.conf" ]]; then
      break
  fi
  /bin/mv ${include_dir}${file} ${include_dir}20-${file}
done
        fi
    else
        logmessage "Settings for: os_sshd_unused_connection_timeout_configure already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_sshd_unused_connection_timeout_configure has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_sudo_timeout_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * N/A

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sudo_timeout_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sudo_timeout_configure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_sudoers_timestamp_type_configure'))["exempt_reason"]
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
    
#####----- Rule: os_tftpd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7
# * IA-5(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_tftpd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_tftpd_disable'))["exempt_reason"]
EOS
)

os_tftpd_disable_audit_score=$($plb -c "print os_tftpd_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_tftpd_disable_audit_score == "true" ]]; then
        ask 'os_tftpd_disable - Run the command(s)-> /bin/launchctl disable system/com.apple.tftpd ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_tftpd_disable ..."
            /bin/launchctl disable system/com.apple.tftpd
        fi
    else
        logmessage "Settings for: os_tftpd_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_tftpd_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: os_time_server_enabled -----#####
## Addresses the following NIST 800-53 controls: 
# * AU-12(1)
# * SC-45(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_time_server_enabled'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_time_server_enabled'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt_reason"]
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
    
#####----- Rule: os_uucp_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_uucp_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('os_uucp_disable'))["exempt_reason"]
EOS
)

os_uucp_disable_audit_score=$($plb -c "print os_uucp_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $os_uucp_disable_audit_score == "true" ]]; then
        ask 'os_uucp_disable - Run the command(s)-> /bin/launchctl disable system/com.apple.uucp ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: os_uucp_disable ..."
            /bin/launchctl disable system/com.apple.uucp
        fi
    else
        logmessage "Settings for: os_uucp_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "os_uucp_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: pwpolicy_account_inactivity_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-2(3)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_account_inactivity_enforce'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_account_inactivity_enforce'))["exempt_reason"]
EOS
)

pwpolicy_account_inactivity_enforce_audit_score=$($plb -c "print pwpolicy_account_inactivity_enforce:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $pwpolicy_account_inactivity_enforce_audit_score == "true" ]]; then
        ask 'pwpolicy_account_inactivity_enforce - Run the command(s)-> /usr/bin/pwpolicy setaccountpolicies $pwpolicy_file ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: pwpolicy_account_inactivity_enforce ..."
            /usr/bin/pwpolicy setaccountpolicies $pwpolicy_file
        fi
    else
        logmessage "Settings for: pwpolicy_account_inactivity_enforce already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "pwpolicy_account_inactivity_enforce has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: pwpolicy_minimum_lifetime_enforce -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-5

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_minimum_lifetime_enforce'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('pwpolicy_minimum_lifetime_enforce'))["exempt_reason"]
EOS
)

pwpolicy_minimum_lifetime_enforce_audit_score=$($plb -c "print pwpolicy_minimum_lifetime_enforce:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $pwpolicy_minimum_lifetime_enforce_audit_score == "true" ]]; then
        ask 'pwpolicy_minimum_lifetime_enforce - Run the command(s)-> /usr/bin/pwpolicy setaccountpolicies $pwpolicy_file ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: pwpolicy_minimum_lifetime_enforce ..."
            /usr/bin/pwpolicy setaccountpolicies $pwpolicy_file
        fi
    else
        logmessage "Settings for: pwpolicy_minimum_lifetime_enforce already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "pwpolicy_minimum_lifetime_enforce has an exemption, remediation skipped (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_cd_dvd_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_cd_dvd_sharing_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_firewall_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_firewall_enable'))["exempt_reason"]
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
    
#####----- Rule: system_settings_gatekeeper_identified_developers_allowed -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-14
# * SI-7(1), SI-7(15)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_gatekeeper_identified_developers_allowed'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_gatekeeper_identified_developers_allowed'))["exempt_reason"]
EOS
)

system_settings_gatekeeper_identified_developers_allowed_audit_score=$($plb -c "print system_settings_gatekeeper_identified_developers_allowed:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_gatekeeper_identified_developers_allowed_audit_score == "true" ]]; then
        ask 'system_settings_gatekeeper_identified_developers_allowed - Run the command(s)-> /usr/sbin/spctl --global-enable; /usr/sbin/spctl --enable ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_gatekeeper_identified_developers_allowed ..."
            /usr/sbin/spctl --global-enable; /usr/sbin/spctl --enable
        fi
    else
        logmessage "Settings for: system_settings_gatekeeper_identified_developers_allowed already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_gatekeeper_identified_developers_allowed has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_location_services_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)
# * SC-7(10)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_location_services_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_location_services_disable'))["exempt_reason"]
EOS
)

system_settings_location_services_disable_audit_score=$($plb -c "print system_settings_location_services_disable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_location_services_disable_audit_score == "true" ]]; then
        ask 'system_settings_location_services_disable - Run the command(s)-> /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool false; 
pid=$(/bin/launchctl list | /usr/bin/awk '"'"'/com.apple.locationd/ { print $1 }'"'"')
kill -9 $pid ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_location_services_disable ..."
            /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -bool false; 
pid=$(/bin/launchctl list | /usr/bin/awk '/com.apple.locationd/ { print $1 }')
kill -9 $pid
        fi
    else
        logmessage "Settings for: system_settings_location_services_disable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_location_services_disable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_printer_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_printer_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_printer_sharing_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_rae_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_rae_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_remote_management_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_remote_management_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_smbd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_smbd_disable'))["exempt_reason"]
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
    
#####----- Rule: system_settings_ssh_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7, CM-7(1)
# * IA-2(8)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_ssh_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_ssh_enable'))["exempt_reason"]
EOS
)

system_settings_ssh_enable_audit_score=$($plb -c "print system_settings_ssh_enable:finding" $audit_plist)
if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
    if [[ $system_settings_ssh_enable_audit_score == "true" ]]; then
        ask 'system_settings_ssh_enable - Run the command(s)-> /bin/launchctl enable system/com.openssh.sshd ' N
        if [[ $? == 0 ]]; then
            logmessage "Running the command to configure the settings for: system_settings_ssh_enable ..."
            /bin/launchctl enable system/com.openssh.sshd
        fi
    else
        logmessage "Settings for: system_settings_ssh_enable already configured, continuing..."
    fi
elif [[ ! -z "$exempt_reason" ]];then
    logmessage "system_settings_ssh_enable has an exemption, remediation skipped (Reason: "$exempt_reason")"
fi
    
#####----- Rule: system_settings_system_wide_preferences_configure -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-6, AC-6(1), AC-6(2)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.stig.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt_reason"]
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
    