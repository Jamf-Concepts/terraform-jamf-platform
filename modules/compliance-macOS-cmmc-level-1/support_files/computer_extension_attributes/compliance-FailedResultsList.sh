#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Copyright (c) 2022 Jamf.  All rights reserved.
#
#       Redistribution and use in source and binary forms, with or without
#       modification, are permitted provided that the following conditions are met:
#               * Redistributions of source code must retain the above copyright
#                 notice, this list of conditions and the following disclaimer.
#               * Redistributions in binary form must reproduce the above copyright
#                 notice, this list of conditions and the following disclaimer in the
#                 documentation and/or other materials provided with the distribution.
#               * Neither the name of the Jamf nor the names of its contributors may be
#                 used to endorse or promote products derived from this software without
#                 specific prior written permission.
#
#       THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#       EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#       WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#       DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#       DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#       (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#       LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#       ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#       (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#       SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
######
# INSTRUCTIONS
# This Jamf Extension Attribute is used in conjunction with the macOS Security Compliance project (mSCP)
# https://github.com/usnistgov/macos_security
#
# Upload the following text into Jamf Pro Extension Attribute section.
#
# Used to gather the list of failed controls from the compliance audit.
######

audit=$(/bin/ls -l /Library/Preferences | /usr/bin/grep 'org.*.audit.plist' | /usr/bin/awk '{print $NF}')
FAILED_RULES=()
if [[ ! -z "$audit" ]]; then

    count=$(echo "$audit" | /usr/bin/wc -l | /usr/bin/xargs)
    if [[ "$count" == 1 ]]; then
        auditfile="/Library/Preferences/${audit}"

        rules=($(/usr/libexec/PlistBuddy -c "print :" "${auditfile}" | /usr/bin/awk '/Dict/ { print $1 }'))
        
        for rule in ${rules[*]}; do
            if [[ $rule == "Dict" ]]; then
                continue
            fi
            FINDING=$(/usr/libexec/PlistBuddy -c "print :$rule:finding" "${auditfile}")
            if [[ "$FINDING" == "true" ]]; then
                FAILED_RULES+=($rule)
            fi
        done
              

    else
        FAILED_RULES="Multiple Baselines Found"
    fi
else
    FAILED_RULES="No Baseline Set"
fi

# sort the results
IFS=$'
' sorted=($(/usr/bin/sort <<<"${FAILED_RULES[*]}")); unset IFS

printf "<result>"
printf "%s
" "${sorted[@]}"
printf "</result>"