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

audit_plist="/Library/Preferences/org.cmmc_lvl1.audit.plist"
audit_log="/Library/Logs/cmmc_lvl1_baseline.log"

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
    lastComplianceScan=$(defaults read /Library/Preferences/org.cmmc_lvl1.audit.plist lastComplianceCheck)

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
        echo "Clearing results from /Library/Preferences/org.cmmc_lvl1.audit.plist"
        rm -f /Library/Preferences/org.cmmc_lvl1.audit.plist
        rm -f /Library/Logs/cmmc_lvl1_baseline.log
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey("$rule"))["exempt"]
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
 	echo "$(date -u) Beginning cmmc_lvl1 baseline scan" >> "$audit_log"
else
 	echo "$(date -u) Beginning cmmc_lvl1 baseline scan" > "$audit_log"
fi

# run mcxrefresh
/usr/bin/mcxrefresh -u $CURR_USER_UID

# write timestamp of last compliance check
/usr/bin/defaults write "$audit_plist" lastComplianceCheck "$(date +"%Y-%m-%d %H:%M:%S%z")"
    
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('auth_smartcard_allow'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('auth_smartcard_allow'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - auth_smartcard_allow passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_smartcard_allow failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_allow" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - auth_smartcard_allow failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "auth_smartcard_allow failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_allow" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - auth_smartcard_allow failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "auth_smartcard_allow does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" auth_smartcard_allow -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('auth_smartcard_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('auth_smartcard_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - auth_smartcard_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_smartcard_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - auth_smartcard_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "auth_smartcard_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_smartcard_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_smartcard_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - auth_smartcard_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('auth_ssh_password_authentication_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('auth_ssh_password_authentication_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - auth_ssh_password_authentication_disable passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "auth_ssh_password_authentication_disable failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_ssh_password_authentication_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - auth_ssh_password_authentication_disable failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "auth_ssh_password_authentication_disable failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "auth_ssh_password_authentication_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" auth_ssh_password_authentication_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - auth_ssh_password_authentication_disable failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_addressbook_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_addressbook_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_addressbook_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_addressbook_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_addressbook_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_addressbook_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_addressbook_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_addressbook_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_addressbook_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_addressbook_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_addressbook_disable -dict-add finding -bool NO
fi

#####----- Rule: icloud_appleid_system_settings_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20, AC-20(1)
# * CM-7, CM-7(1)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles show -output stdout-xml | /usr/bin/xmllint --xpath '//key[text()="DisabledSystemSettings"]/following-sibling::*[1]' - | /usr/bin/grep -c "com.apple.systempreferences.AppleIDSettings"
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_appleid_system_settings_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_appleid_system_settings_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "icloud_appleid_system_settings_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "icloud_appleid_system_settings_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" icloud_appleid_system_settings_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "icloud_appleid_system_settings_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" icloud_appleid_system_settings_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_appleid_system_settings_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_appleid_system_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" icloud_appleid_system_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_appleid_system_settings_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_appleid_system_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_appleid_system_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "icloud_appleid_system_settings_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_appleid_system_settings_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_appleid_system_settings_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_appleid_system_settings_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_appleid_system_settings_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "icloud_appleid_system_settings_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" icloud_appleid_system_settings_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_bookmarks_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_bookmarks_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_bookmarks_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_bookmarks_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_bookmarks_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_bookmarks_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_bookmarks_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_bookmarks_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_bookmarks_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_bookmarks_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_calendar_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_calendar_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_calendar_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_calendar_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_calendar_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_calendar_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_calendar_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_calendar_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_calendar_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_calendar_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_drive_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_drive_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_drive_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_drive_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_drive_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_drive_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_drive_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_drive_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_drive_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_drive_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_freeform_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_freeform_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_freeform_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_freeform_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_freeform_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_freeform_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_freeform_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_freeform_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_freeform_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_freeform_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_game_center_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_game_center_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_game_center_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_game_center_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_game_center_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_game_center_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_game_center_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_game_center_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_game_center_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_game_center_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_keychain_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_keychain_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_keychain_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_keychain_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_keychain_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_keychain_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_keychain_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_keychain_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_keychain_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_keychain_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_mail_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_mail_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_mail_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_mail_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_mail_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_mail_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_mail_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_mail_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_mail_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_mail_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_notes_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_notes_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_notes_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_notes_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_notes_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_notes_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_notes_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_notes_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_notes_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_notes_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_photos_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_photos_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_photos_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_photos_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_photos_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_photos_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_photos_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_photos_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_photos_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_photos_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_private_relay_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_private_relay_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_private_relay_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_private_relay_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_private_relay_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_private_relay_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_private_relay_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_private_relay_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_private_relay_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_private_relay_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_reminders_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_reminders_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_reminders_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_reminders_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_reminders_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_reminders_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_reminders_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_reminders_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_reminders_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_reminders_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_sync_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('icloud_sync_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_sync_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "icloud_sync_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_sync_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_sync_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "icloud_sync_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "icloud_sync_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" icloud_sync_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - icloud_sync_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_account_modification_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_account_modification_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_account_modification_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_account_modification_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_account_modification_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_account_modification_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_account_modification_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_account_modification_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_account_modification_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_account_modification_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_airdrop_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_airdrop_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_airdrop_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_airdrop_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_airdrop_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_airdrop_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_airdrop_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_airdrop_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_airdrop_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_appleid_prompt_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_appleid_prompt_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_appleid_prompt_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_appleid_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_appleid_prompt_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_appleid_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_appleid_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_appleid_prompt_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_appleid_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_appleid_prompt_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_appleid_prompt_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_authenticated_root_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_authenticated_root_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_authenticated_root_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_authenticated_root_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_authenticated_root_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_authenticated_root_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_authenticated_root_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_authenticated_root_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_authenticated_root_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_config_data_install_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_config_data_install_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_config_data_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_config_data_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_config_data_install_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_config_data_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_config_data_install_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" os_config_data_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_config_data_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_dictation_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_dictation_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_dictation_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_dictation_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_dictation_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_dictation_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_dictation_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_dictation_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_dictation_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_dictation_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_dictation_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_filevault_autologin_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_filevault_autologin_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_filevault_autologin_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_filevault_autologin_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_filevault_autologin_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_filevault_autologin_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_filevault_autologin_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_filevault_autologin_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_filevault_autologin_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_filevault_autologin_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_filevault_autologin_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_firewall_log_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_firewall_log_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_firewall_log_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_firewall_log_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_firewall_log_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_firewall_log_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_firewall_log_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_firewall_log_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_firewall_log_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_firewall_log_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_firewall_log_enable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_firmware_password_require'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_firmware_password_require'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_firmware_password_require passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_firmware_password_require failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add finding -bool YES
            if [[ ! "$customref" == "os_firmware_password_require" ]]; then
                /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_firmware_password_require failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_firmware_password_require failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add finding -bool YES
            if [[ ! "$customref" == "os_firmware_password_require" ]]; then
              /usr/bin/defaults write "$audit_plist" os_firmware_password_require -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_firmware_password_require failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_gatekeeper_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_gatekeeper_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_gatekeeper_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_gatekeeper_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_gatekeeper_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_gatekeeper_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_gatekeeper_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_gatekeeper_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_gatekeeper_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_gatekeeper_enable -dict-add finding -bool NO
fi

#####----- Rule: os_gatekeeper_rearm -----#####
## Addresses the following NIST 800-53 controls: 
# * CM-5
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.security')\
.objectForKey('GKAutoRearm').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_gatekeeper_rearm'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_gatekeeper_rearm'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_gatekeeper_rearm" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_gatekeeper_rearm passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_gatekeeper_rearm -dict-add finding -bool NO
        if [[ ! "$customref" == "os_gatekeeper_rearm" ]]; then
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_rearm -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_gatekeeper_rearm passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_gatekeeper_rearm failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_rearm -dict-add finding -bool YES
            if [[ ! "$customref" == "os_gatekeeper_rearm" ]]; then
                /usr/bin/defaults write "$audit_plist" os_gatekeeper_rearm -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_gatekeeper_rearm failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_gatekeeper_rearm failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_gatekeeper_rearm -dict-add finding -bool YES
            if [[ ! "$customref" == "os_gatekeeper_rearm" ]]; then
              /usr/bin/defaults write "$audit_plist" os_gatekeeper_rearm -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_gatekeeper_rearm failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_gatekeeper_rearm does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_gatekeeper_rearm -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_handoff_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_handoff_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_handoff_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_handoff_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_handoff_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_handoff_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_handoff_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_handoff_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_handoff_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_handoff_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_home_folders_secure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_home_folders_secure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_home_folders_secure passed (Result: $result_value, Expected: "{'integer': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_home_folders_secure failed (Result: $result_value, Expected: \"{'integer': 0}\")"
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_home_folders_secure" ]]; then
                /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}")"
        else
            logmessage "os_home_folders_secure failed (Result: $result_value, Expected: \"{'integer': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add finding -bool YES
            if [[ ! "$customref" == "os_home_folders_secure" ]]; then
              /usr/bin/defaults write "$audit_plist" os_home_folders_secure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_home_folders_secure failed (Result: $result_value, Expected: "{'integer': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_httpd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_httpd_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_httpd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_httpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_httpd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_httpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_httpd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_httpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_httpd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_icloud_storage_prompt_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_icloud_storage_prompt_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_icloud_storage_prompt_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_icloud_storage_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_icloud_storage_prompt_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_icloud_storage_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_icloud_storage_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_icloud_storage_prompt_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_icloud_storage_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_icloud_storage_prompt_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_icloud_storage_prompt_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_nfsd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_nfsd_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_nfsd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_nfsd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_nfsd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_nfsd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_nfsd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_nfsd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_nfsd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_on_device_dictation_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_on_device_dictation_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_on_device_dictation_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_on_device_dictation_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_on_device_dictation_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_on_device_dictation_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_on_device_dictation_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "os_on_device_dictation_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_on_device_dictation_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_on_device_dictation_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_on_device_dictation_enforce -dict-add finding -bool NO
fi

#####----- Rule: os_rapid_security_response_allow -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-2, SI-2(5)
# * SI-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowRapidSecurityResponseInstallation').js
EOS
)
    # expected result {'string': 'true'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_rapid_security_response_allow'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_rapid_security_response_allow'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_rapid_security_response_allow" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "true" ]]; then
        logmessage "os_rapid_security_response_allow passed (Result: $result_value, Expected: \"{'string': 'true'}\")"
        /usr/bin/defaults write "$audit_plist" os_rapid_security_response_allow -dict-add finding -bool NO
        if [[ ! "$customref" == "os_rapid_security_response_allow" ]]; then
            /usr/bin/defaults write "$audit_plist" os_rapid_security_response_allow -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_rapid_security_response_allow passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_rapid_security_response_allow failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_rapid_security_response_allow -dict-add finding -bool YES
            if [[ ! "$customref" == "os_rapid_security_response_allow" ]]; then
                /usr/bin/defaults write "$audit_plist" os_rapid_security_response_allow -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_rapid_security_response_allow failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_rapid_security_response_allow failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_rapid_security_response_allow -dict-add finding -bool YES
            if [[ ! "$customref" == "os_rapid_security_response_allow" ]]; then
              /usr/bin/defaults write "$audit_plist" os_rapid_security_response_allow -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_rapid_security_response_allow failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_rapid_security_response_allow does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_rapid_security_response_allow -dict-add finding -bool NO
fi

#####----- Rule: os_rapid_security_response_removal_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * SI-2, SI-2(5)
# * SI-3
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/osascript -l JavaScript << EOS
$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess')\
.objectForKey('allowRapidSecurityResponseRemoval').js
EOS
)
    # expected result {'string': 'false'}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_rapid_security_response_removal_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_rapid_security_response_removal_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "os_rapid_security_response_removal_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "false" ]]; then
        logmessage "os_rapid_security_response_removal_disable passed (Result: $result_value, Expected: \"{'string': 'false'}\")"
        /usr/bin/defaults write "$audit_plist" os_rapid_security_response_removal_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "os_rapid_security_response_removal_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" os_rapid_security_response_removal_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_rapid_security_response_removal_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_rapid_security_response_removal_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" os_rapid_security_response_removal_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_rapid_security_response_removal_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_rapid_security_response_removal_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_rapid_security_response_removal_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "os_rapid_security_response_removal_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_rapid_security_response_removal_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_rapid_security_response_removal_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_rapid_security_response_removal_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_rapid_security_response_removal_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_rapid_security_response_removal_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_rapid_security_response_removal_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_recovery_lock_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_recovery_lock_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_recovery_lock_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_recovery_lock_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_recovery_lock_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_recovery_lock_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_recovery_lock_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_recovery_lock_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_recovery_lock_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_recovery_lock_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_root_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_root_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_root_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_root_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_root_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_root_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_root_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_root_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_root_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_root_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_sip_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_sip_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_sip_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_sip_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sip_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_sip_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_sip_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_sip_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_sip_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_siri_prompt_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_siri_prompt_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_siri_prompt_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_siri_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_siri_prompt_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_siri_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_siri_prompt_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_siri_prompt_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_siri_prompt_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_siri_prompt_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_siri_prompt_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_skip_unlock_with_watch_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_skip_unlock_with_watch_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_skip_unlock_with_watch_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_skip_unlock_with_watch_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_skip_unlock_with_watch_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_skip_unlock_with_watch_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "os_skip_unlock_with_watch_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_skip_unlock_with_watch_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_skip_unlock_with_watch_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_skip_unlock_with_watch_enable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_skip_unlock_with_watch_enable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_tftpd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_tftpd_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_tftpd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_tftpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_tftpd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_tftpd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_tftpd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_tftpd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_tftpd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_tftpd_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_tftpd_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_unlock_active_user_session_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_unlock_active_user_session_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_unlock_active_user_session_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_unlock_active_user_session_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_unlock_active_user_session_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_unlock_active_user_session_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_unlock_active_user_session_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_unlock_active_user_session_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_uucp_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_uucp_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - os_uucp_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "os_uucp_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_uucp_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_uucp_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "os_uucp_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "os_uucp_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - os_uucp_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "os_uucp_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" os_uucp_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_automatic_login_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_automatic_login_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_automatic_login_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_automatic_login_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_automatic_login_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_automatic_login_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_automatic_login_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_automatic_login_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_automatic_login_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_automatic_login_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_bluetooth_sharing_disable passed (Result: $result_value, Expected: "{'boolean': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}")"
        else
            logmessage "system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_bluetooth_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_bluetooth_sharing_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_bluetooth_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_bluetooth_sharing_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_critical_update_install_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_critical_update_install_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_critical_update_install_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_critical_update_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_critical_update_install_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_critical_update_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_critical_update_install_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_critical_update_install_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_critical_update_install_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_critical_update_install_enforce does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_critical_update_install_enforce -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_diagnostics_reports_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_diagnostics_reports_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_diagnostics_reports_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_diagnostics_reports_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_diagnostics_reports_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_diagnostics_reports_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_diagnostics_reports_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_diagnostics_reports_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_diagnostics_reports_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_diagnostics_reports_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_diagnostics_reports_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_find_my_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_find_my_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_find_my_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_find_my_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_find_my_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_find_my_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_find_my_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_find_my_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_find_my_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_find_my_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_firewall_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_firewall_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_firewall_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_firewall_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_firewall_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_firewall_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_firewall_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_firewall_stealth_mode_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_firewall_stealth_mode_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_firewall_stealth_mode_enable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_firewall_stealth_mode_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_stealth_mode_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_firewall_stealth_mode_enable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_firewall_stealth_mode_enable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_firewall_stealth_mode_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_firewall_stealth_mode_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_firewall_stealth_mode_enable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_guest_access_smb_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_guest_access_smb_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_guest_access_smb_disable passed (Result: $result_value, Expected: "{'boolean': 0}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_guest_access_smb_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_access_smb_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_guest_access_smb_disable failed (Result: $result_value, Expected: "{'boolean': 0}")"
        else
            logmessage "system_settings_guest_access_smb_disable failed (Result: $result_value, Expected: \"{'boolean': 0}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_access_smb_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_guest_access_smb_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_guest_access_smb_disable failed (Result: $result_value, Expected: "{'boolean': 0}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_guest_account_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_guest_account_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_guest_account_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_guest_account_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_account_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_guest_account_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_guest_account_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_guest_account_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_guest_account_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_guest_account_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_improve_siri_dictation_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_improve_siri_dictation_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_improve_siri_dictation_disable passed (Result: $result_value, Expected: "{'integer': 2}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_improve_siri_dictation_disable failed (Result: $result_value, Expected: \"{'integer': 2}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_improve_siri_dictation_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_improve_siri_dictation_disable failed (Result: $result_value, Expected: "{'integer': 2}")"
        else
            logmessage "system_settings_improve_siri_dictation_disable failed (Result: $result_value, Expected: \"{'integer': 2}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_improve_siri_dictation_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_improve_siri_dictation_disable failed (Result: $result_value, Expected: "{'integer': 2}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_improve_siri_dictation_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_improve_siri_dictation_disable -dict-add finding -bool NO
fi

#####----- Rule: system_settings_internet_accounts_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-20
# * CM-7, CM-7(1), CM-7(5)
rule_arch=""
if [[ "$arch" == "$rule_arch" ]] || [[ -z "$rule_arch" ]]; then
    unset result_value
    result_value=$(/usr/bin/profiles show -output stdout-xml | /usr/bin/xmllint --xpath '//key[text()="DisabledSystemSettings"]/following-sibling::*[1]' - | /usr/bin/grep -c com.apple.Internet-Accounts-Settings.extension
)
    # expected result {'integer': 1}


    # check to see if rule is exempt
    unset exempt
    unset exempt_reason

    exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_internet_accounts_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_internet_accounts_disable'))["exempt_reason"]
EOS
)   
    customref="$(echo "system_settings_internet_accounts_disable" | rev | cut -d ' ' -f 2- | rev)"
    customref="$(echo "$customref" | tr " " ",")"
    if [[ $result_value == "1" ]]; then
        logmessage "system_settings_internet_accounts_disable passed (Result: $result_value, Expected: \"{'integer': 1}\")"
        /usr/bin/defaults write "$audit_plist" system_settings_internet_accounts_disable -dict-add finding -bool NO
        if [[ ! "$customref" == "system_settings_internet_accounts_disable" ]]; then
            /usr/bin/defaults write "$audit_plist" system_settings_internet_accounts_disable -dict-add reference -string "$customref"
        fi
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_internet_accounts_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_internet_accounts_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_internet_accounts_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_internet_accounts_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_internet_accounts_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_internet_accounts_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_internet_accounts_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_internet_accounts_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_internet_accounts_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_internet_accounts_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_internet_accounts_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_internet_accounts_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_internet_accounts_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_internet_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_internet_sharing_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_internet_sharing_disable passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_internet_sharing_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_internet_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_internet_sharing_disable failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_internet_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_internet_sharing_disable failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_internet_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_internet_sharing_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_loginwindow_prompt_username_password_enforce'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_loginwindow_prompt_username_password_enforce'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_loginwindow_prompt_username_password_enforce passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_loginwindow_prompt_username_password_enforce" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_loginwindow_prompt_username_password_enforce" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_loginwindow_prompt_username_password_enforce -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_loginwindow_prompt_username_password_enforce failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_media_sharing_disabled'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_media_sharing_disabled'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_media_sharing_disabled passed (Result: $result_value, Expected: "{'string': 'true'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_media_sharing_disabled failed (Result: $result_value, Expected: \"{'string': 'true'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_media_sharing_disabled" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_media_sharing_disabled failed (Result: $result_value, Expected: "{'string': 'true'}")"
        else
            logmessage "system_settings_media_sharing_disabled failed (Result: $result_value, Expected: \"{'string': 'true'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_media_sharing_disabled" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_media_sharing_disabled failed (Result: $result_value, Expected: "{'string': 'true'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_media_sharing_disabled does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_media_sharing_disabled -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_personalized_advertising_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_personalized_advertising_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_personalized_advertising_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_personalized_advertising_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_personalized_advertising_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_personalized_advertising_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_personalized_advertising_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_personalized_advertising_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_rae_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_rae_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_rae_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_rae_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_rae_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_rae_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_rae_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_rae_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_rae_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_rae_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_screen_sharing_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_screen_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screen_sharing_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_screen_sharing_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_screen_sharing_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_screen_sharing_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_screen_sharing_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_screen_sharing_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_siri_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_siri_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_siri_disable passed (Result: $result_value, Expected: "{'string': 'false'}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_siri_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_siri_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_siri_disable failed (Result: $result_value, Expected: "{'string': 'false'}")"
        else
            logmessage "system_settings_siri_disable failed (Result: $result_value, Expected: \"{'string': 'false'}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_siri_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_siri_disable failed (Result: $result_value, Expected: "{'string': 'false'}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_siri_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_siri_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_smbd_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_smbd_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_smbd_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_smbd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_smbd_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_smbd_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_smbd_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_smbd_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_smbd_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_smbd_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_ssh_disable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_ssh_disable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_ssh_disable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_ssh_disable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_ssh_disable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_ssh_disable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_ssh_disable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_ssh_disable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_ssh_disable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_ssh_disable does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_ssh_disable -dict-add finding -bool NO
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_ssh_enable'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_ssh_enable'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_ssh_enable passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_ssh_enable failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_ssh_enable" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_ssh_enable failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_ssh_enable failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_ssh_enable" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_ssh_enable -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_ssh_enable failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt"]
EOS
)
    exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt_reason"]
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
        /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_system_wide_preferences_configure passed (Result: $result_value, Expected: "{'integer': 1}")"
    else
        if [[ ! $exempt == "1" ]] || [[ -z $exempt ]];then
            logmessage "system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: \"{'integer': 1}\")"
            /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_system_wide_preferences_configure" ]]; then
                /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}")"
        else
            logmessage "system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: \"{'integer': 1}\") - Exemption Allowed (Reason: \"$exempt_reason\")"
            /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool YES
            if [[ ! "$customref" == "system_settings_system_wide_preferences_configure" ]]; then
              /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add reference -string "$customref"
            fi
            /usr/bin/logger "mSCP: cmmc_lvl1 - system_settings_system_wide_preferences_configure failed (Result: $result_value, Expected: "{'integer': 1}") - Exemption Allowed (Reason: "$exempt_reason")"
            /bin/sleep 1
        fi
    fi


else
    logmessage "system_settings_system_wide_preferences_configure does not apply to this architecture"
    /usr/bin/defaults write "$audit_plist" system_settings_system_wide_preferences_configure -dict-add finding -bool NO
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


    
#####----- Rule: auth_ssh_password_authentication_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(1), IA-2(2), IA-2(6), IA-2(8)
# * IA-5(2)
# * MA-4

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('auth_ssh_password_authentication_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('auth_ssh_password_authentication_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_authenticated_root_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_authenticated_root_enable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_gatekeeper_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_gatekeeper_enable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_home_folders_secure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_home_folders_secure'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_httpd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_httpd_disable'))["exempt_reason"]
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
    
#####----- Rule: os_nfsd_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_nfsd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_nfsd_disable'))["exempt_reason"]
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
    
#####----- Rule: os_root_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_root_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_root_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_sip_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_sip_enable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_tftpd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_tftpd_disable'))["exempt_reason"]
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
    
#####----- Rule: os_unlock_active_user_session_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * IA-2, IA-2(5)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_unlock_active_user_session_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_uucp_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('os_uucp_disable'))["exempt_reason"]
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
    
#####----- Rule: system_settings_bluetooth_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-18(4)
# * AC-3
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_bluetooth_sharing_disable'))["exempt_reason"]
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
    
#####----- Rule: system_settings_firewall_enable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-4
# * CM-7, CM-7(1)
# * SC-7, SC-7(12)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_firewall_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_firewall_enable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_firewall_stealth_mode_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_firewall_stealth_mode_enable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_guest_access_smb_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_guest_access_smb_disable'))["exempt_reason"]
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
    
#####----- Rule: system_settings_rae_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_rae_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_rae_disable'))["exempt_reason"]
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
    
#####----- Rule: system_settings_screen_sharing_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * AC-3
# * CM-7

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_screen_sharing_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_smbd_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_smbd_disable'))["exempt_reason"]
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
    
#####----- Rule: system_settings_ssh_disable -----#####
## Addresses the following NIST 800-53 controls: 
# * AC-17
# * CM-7, CM-7(1)

# check to see if rule is exempt
unset exempt
unset exempt_reason

exempt=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_ssh_disable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_ssh_disable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_ssh_enable'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_ssh_enable'))["exempt_reason"]
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
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt"]
EOS
)

exempt_reason=$(/usr/bin/osascript -l JavaScript << EOS 2>/dev/null
ObjC.unwrap($.NSUserDefaults.alloc.initWithSuiteName('org.cmmc_lvl1.audit').objectForKey('system_settings_system_wide_preferences_configure'))["exempt_reason"]
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
    