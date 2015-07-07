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
#
#	The purpose of this script is to allow a new individual recovery key to be issued
#	if the current key is invalid and the management account is not enabled for FV2,
#	or if the machine was encrypted outside of the JSS.
#
#	First put a configuration profile for FV2 recovery key redirection in place.
#	Ensure keys are being redirected to your JSS.
#
#	This script will prompt the user for their password so a new FV2 individual
#	recovery key can be issued and redirected to the JSS.
#
####################################################################################################
# 
# HISTORY
#
#	-Created by Sam Fortuna on Sept. 5, 2014
#	-Updated by Sam Fortuna on Nov. 18, 2014
#		-Added support for 10.10
#   	-Updated by Sam Fortuna on June 23, 2015
#       	-Properly escapes special characters in user passwords
#
####################################################################################################
#
## Get the logged in user's name
userName=$(/usr/bin/stat -f%Su /dev/console)

## Get the OS version
OS=`/usr/bin/sw_vers -productVersion | awk -F. {'print $2'}`

## This first user check sees if the logged in account is already authorized with FileVault 2
userCheck=`fdesetup list | awk -v usrN="$userName" -F, 'index($0, usrN) {print $1}'`
if [ "${userCheck}" != "${userName}" ]; then
	echo "This user is not a FileVault 2 enabled user."
	exit 3
fi

## Check to see if the encryption process is complete
encryptCheck=`fdesetup status`
statusCheck=$(echo "${encryptCheck}" | grep "FileVault is On.")
expectedStatus="FileVault is On."
if [ "${statusCheck}" != "${expectedStatus}" ]; then
	echo "The encryption process has not completed."
	echo "${encryptCheck}"
	exit 4
fi

## Get the logged in user's password via a prompt
echo "Prompting ${userName} for their login password."
userPass="$(/usr/bin/osascript -e 'Tell application "System Events" to display dialog "Please enter your login password:" default answer "" with title "Login Password" with text buttons {"Ok"} default button 1 with hidden answer' -e 'text returned of result')"

echo "Issuing new recovery key"

if [[ $OS -ge 9  ]]; then
	## This "expect" block will populate answers for the fdesetup prompts that normally occur while hiding them from output
	expect -c "
	log_user 0
	spawn fdesetup changerecovery -personal
	expect \"Enter a password for '/', or the recovery key:\"
	send "{${userPass}}"
	send \r
	log_user 1
	expect eof
	"
else
	echo "OS version not 10.9+ or OS version unrecognized"
	echo "$(/usr/bin/sw_vers -productVersion)"
	exit 5
fi

exit 0
