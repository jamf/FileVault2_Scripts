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
#   This script was designed to enable the managment account the ability to unlock
#   a drive that was originally encrypted with the currently logged in user's account.
#   The script will prompt the user for their credentials.
#   
#   This script was designed to be run via policy at login or via Self Service.  The encryption
#   process must be fully completed before this script can be successfully executed.  
#
####################################################################################################
# 
# HISTORY
#
#   -Created by Bryson Tyrrell on November 5th, 2012
#   -Updated by Sam Fortuna on July 31, 2013
#       -Improved Error Handling
#   -Updated by Sam Fortuna on January 14, 2014
#       -Added logic for Mavericks OS
#   -Updated by Sam Fortuna on December 15, 2014
#       -Added logic for Yosemite OS
#       -Improved OS vesion handling
#
####################################################################################################
#
## Self Service policy to add the logged in user to the enabled list
## of FileVault 2 users.

## Pass the credentials for an admin account that is authorized with FileVault 2
adminName=$4
adminPass=$5

if [ "${adminName}" == "" ]; then
    echo "Username undefined.  Please pass the management account username in parameter 4"
    exit 1
fi

if [ "${adminPass}" == "" ]; then
    echo "Password undefined.  Please pass the management account password in parameter 5"
    exit 2
fi

## Get the logged in user's name
userName=`defaults read /Library/Preferences/com.apple.loginwindow lastUserName`

## Get the OS version
OS=`/usr/bin/sw_vers -productVersion | awk -F. {'print $2'}`

## This first user check sees if the logged in account is already authorized with FileVault 2
userCheck=`fdesetup list | awk -v usrN="$adminName" -F, 'index($0, usrN) {print $1}'`
if [ "${userCheck}" == "${adminName}" ]; then
    echo "This user is already added to the FileVault 2 list."
    exit 3
fi

## Check to see if the encryption process is complete
encryptCheck=`fdesetup status`
statusCheck=$(echo "${encryptCheck}" | grep "FileVault is On.")
expectedStatus="FileVault is On."
if [ "${statusCheck}" != "${expectedStatus}" ]; then
    echo "The encryption process has not completed, unable to add user at this time."
    echo "${encryptCheck}"
    exit 4
fi

## Get the logged in user's password via a prompt
echo "Prompting ${userName} for their login password."
userPass="$(/usr/bin/osascript -e 'Tell application "System Events" to display dialog "Please enter your login password:" default answer "" with title "Login Password" with text buttons {"Ok"} default button 1 with hidden answer' -e 'text returned of result')"

echo "Adding user to FileVault 2 list."

if [[ $OS -lt 8 ]]; then
    echo "OS version not 10.8+ or OS version unrecognized"
    echo "$(/usr/bin/sw_vers -productVersion)"
    exit 5

elif [[ $OS -eq 8 ]]; then

    ## This "expect" block will populate answers for the fdesetup prompts that normally occur while hiding them from output
    expect -c "
    log_user 0
    spawn fdesetup add -usertoadd $adminName
    expect \"Enter the primary user name:\"
    send ${userName}\r
    expect \"Enter the password for the user '$userName':\"
    send ${userPass}\r
    expect \"Enter the password for the added user '$adminName':\"
    send ${adminPass}\r
    log_user 1
    expect eof
    "
elif [[ $OS -gt 8 ]]; then

    ## This "expect" block will populate answers for the fdesetup prompts that normally occur while hiding them from output
    expect -c "
    log_user 0
    spawn fdesetup add -usertoadd $adminName
    expect \"Enter a password*\"
    send ${userPass}\r
    expect \"Enter the password*\"
    send ${adminPass}\r
    log_user 1
    expect eof
    "
fi

## This second user check sees if the logged in account was successfully added to the FileVault 2 list
userCheck=`fdesetup list | awk -v usrN="$adminName" -F, 'index($0, usrN) {print $1}'`
if [ "${userCheck}" != "${adminName}" ]; then
    echo "Failed to add user to FileVault 2 list."
    echo "Currently enabled users:"
    echo "${userCheck}"
    exit 6
fi

echo "${adminName} has been added to the FileVault 2 list."

exit 0
