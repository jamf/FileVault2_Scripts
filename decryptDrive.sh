#!/bin/bash

####################################################################################################
#
# Copyright (c) 2013, JAMF Software, LLC.  All rights reserved.
#
#       Redistribution and use in source and binary forms, with or without
#       modification, are permitted provided that the following conditions are met:
#               * Redistributions of source code must retain the above copyright
#                 notice, this list of conditions and the following disclaimer.
#               * Redistributions in binary form must reproduce the above copyright
#                 notice, this list of conditions and the following disclaimer in the
#                 documentation and/or other materials provided with the distribution.
#               * Neither the name of the JAMF Software, LLC nor the
#                 names of its contributors may be used to endorse or promote products
#                 derived from this software without specific prior written permission.
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
####################################################################################################
#
# Description
#   This script was designed to decrypt a FV2 encrypted drive.  This script must be run
#	while a user that is currently enabled for FV2 is logged in.
#
####################################################################################################
# 
# HISTORY
#
# Created by Sam Fortuna on October 16th, 2013
#
####################################################################################################


## Determine if drive is currently encrypted
fdeStatus=`fdesetup status`

if [[ "${fdeStatus}" == *"FileVault is Off"* ]]; then
	echo "FileVault is not on, exiting now"
	exit 1
fi

## Get the logged in user's name
userName=`defaults read /Library/Preferences/com.apple.loginwindow lastUserName`

## Check if the currently logged in user is authorized with FileVault 2
userCheck=`fdesetup list | awk -v usrN="$userName" -F, 'index($0, usrN) {print $1}'`
if [ "${userCheck}" != "${userName}" ]; then
	echo "This user is not enabled for FileVault 2 access."
	exit 2
fi

## Get the logged in user's password via a prompt
echo "Prompting ${userName} for their login password."
userPass="$(osascript -e 'Tell application "System Events" to display dialog "Please enter your login password:" default answer "" with title "Login Password" with text buttons {"Ok"} default button 1 with hidden answer' -e 'text returned of result')"

## This "expect" block will populate answers for the fdesetup prompts that normally occur while hiding them from output
expect -c "
log_user 0
spawn fdesetup disable
expect \"Enter a password for '/' or recovery key:\"
send ${userPass}\r
log_user 1
expect eof
"

## Give decryption a moment to begin and verify its progress
sleep 10
fdeStatus=`fdesetup status`

if [[ "${fdeStatus}" == *"Decryption"* ]]; then
	echo "FileVault is no longer enabled."
	exit 0
else
	echo "FileVault is On, decryption failed"
	echo "Current FV2 Status: ${fdeStatus}"
	exit 3
fi
