#!/bin/bash

####################################################################################################
#
# Copyright (c) 2017, JAMF Software, LLC.  All rights reserved.
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
# DESCRIPTION
#
# The purpose of this script is to allow a new individual recovery key to be issued
# if the current key is invalid and the management account is not enabled for FV2,
# or if the machine was encrypted outside of the JSS.
#
# First put a configuration profile for FV2 recovery key redirection in place.
# Ensure keys are being redirected to your JSS.
#
# This script will prompt the user for their password so a new FV2 individual
# recovery key can be issued and redirected to the JSS.
#
####################################################################################################
#
# HISTORY
#
# - Created by Sam Fortuna on Sept. 5, 2014
# - Updated by Sam Fortuna on Nov. 18, 2014
#   - Added support for 10.10
# - Updated by Sam Fortuna on June 23, 2015
#   - Properly escapes special characters in user passwords
# - Updated by Bram Cohen on May 27, 2016
#   - Pipe FV key and password to /dev/null
# - Updated by Jordan Wisniewski on Dec 5, 2016
#   - Removed quotes for 'send {${userPass}}     ' so passwords with spaces work.
# - Updated by Shane Brown/Kylie Bareis on Aug 29, 2017
#   - Fixed an issue with usernames that contain sub-string matches of each other.
# - Updated by Bram Cohen on Jan 3, 2018
#   - 10.13 adds a new prompt for username before password in changerecovery
# - Updated by Matt Boyle on July 6, 2018
#   - Error handling, custom Window labels, Messages and FV2 Icon
# - Updated by David Raabe on July 26, 2018
#   - Added Custom Branding to pop up windows
# - Updated by Sebastien Del Saz Alvarez on January 22, 2021
#   - Changed OS variable and relevant if statements to use OS Build rather than OS Version to avoid errors in Big Sur
# - Updated by Aron Smith-Donovan on September 28th, 2022
#   - Added comments + formatting fixes
#   - Replaced orgName variable with new windowTitle variable
####################################################################################################
# 
# PARAMETERS
#  - parameter descriptions indicated when adding script to Jamf
#  - parameter values indicated when deploying script via policy
#  - parameters 1, 2, and 3 are reserved for mount point, computer name, and username (respectively)
# 
# Parameter 4 = Custom organization name (displays in pop-up window)
#   default: blank
# Parameter 5 = # of failed attempts until stop
#   default: 2
# Parameter 6 = Custom text for organizational contact information
#   default: "Please contact IT for further assistance."
# Parameter 7 = Custom brand icon
#   default: Self Service icon
#     if not available, then Jamf icon
#     if not available, then FileVault icon
####################################################################################################

# SET GRAPHICS PATHS
selfServiceBrandIcon="/Users/$3/Library/Application Support/com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"
jamfBrandIcon="/Library/Application Support/JAMF/Jamf.app/Contents/Resources/AppIcon.icns"
fileVaultIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns"


# VALIDATE PARAMETER INPUT & INITIALIZE VARIABLES
## parameter 4 (organization name)
  if [ ! -z "$4" ]; then
    windowTitle="$4 - FileVault Key Reset"
  else
    windowTitle="FileVault Key Reset"
  fi

## parameter 5 (failed attempts before stop)
  try=0
  if [ ! -z "$5" ]; then
    maxTry=$5
  else
    maxTry=2
  fi

## parameter 6 (contact information)
  if [ ! -z "$6" ]; then
    haltMsg="$6"
  else
    haltMsg="Please contact IT for further assistance."
  fi

## parameter 7 (brand icon)
  if [[ ! -z "$7" ]]; then
    brandIcon="$7"
  elif [[ -f $selfServiceBrandIcon ]]; then
    brandIcon=$selfServiceBrandIcon
  elif [[ -f $jamfBrandIcon ]]; then
    brandIcon=$jamfBrandIcon
  else
    brandIcon=$fileVaultIcon
  fi


# RECONAISSANCE
## get the current user's username
  userName=$(/usr/bin/stat -f%Su /dev/console)

## get the UUID of the current user
  userNameUUID=$(dscl . -read /Users/$userName/ GeneratedUID | awk '{print $2}')

## get the OS build
  BUILD=`/usr/bin/sw_vers -buildVersion | awk {'print substr ($0,0,2)'}`


# INITIAL VALIDATION
## check if current user is authorized with FileVault 2
  userCheck=`fdesetup list | awk -v usrN="$userNameUUID" -F, 'match($0, usrN) {print $1}'`
  if [ "${userCheck}" != "${userName}" ]; then
    echo "This user is not a FileVault 2 enabled user."
    exit 3
  fi

## check if encryption is complete
  encryptCheck=`fdesetup status`
  statusCheck=$(echo "${encryptCheck}" | grep "FileVault is On.")
  expectedStatus="FileVault is On."
  if [ "${statusCheck}" != "${expectedStatus}" ]; then
    echo "The encryption process has not completed."
    echo "${encryptCheck}"
    exit 4
  fi


# FUNCTIONS
## passwordPrompt
### get the current user's password via prompt in a pop-up window
  passwordPrompt () {
    # log fxn execution
    echo "Prompting ${userName} for their login password."
    
    # generate pop-up window
    userPass=$(/usr/bin/osascript -e "
    on run
    display dialog \"To generate a new FileVault key\" & return & \"Enter login password for '$userName'\" default answer \"\" with title \"$windowTitle\" buttons {\"Cancel\", \"Ok\"} default button 2 with icon POSIX file \"$brandIcon\" with text and hidden answer
    set userPass to text returned of the result
    return userPass
    end run")

    # exit if user selected "Cancel" in pop-up window
    if [ "$?" == "1" ]; then
      echo "User Canceled"
      exit 0
    fi

    # increment attempt counter
    try=$((try+1))

    # re-issue personal recovery key
    ## the "expect" blocks populate answers for the fdesetup prompts while hiding them from output
    if [[ $BUILD -ge 13 ]] &&  [[ $BUILD -lt 17 ]]; then
      result=$(expect -c "
      log_user 0
      spawn fdesetup changerecovery -personal
      expect \"Enter a password for '/', or the recovery key:\"
      send {${userPass}}   
      send \r
      log_user 1
      expect eof
      " >> /dev/null)
    elif [[ $BUILD -ge 17 ]]; then
      result=$(expect -c "
      log_user 0
      spawn fdesetup changerecovery -personal
      expect \"Enter the user name:\"
      send {${userName}}   
      send \r
      expect \"Enter a password for '/', or the recovery key:\"
      send {${userPass}}   
      send \r
      log_user 1
      expect eof
      ")
    else
      echo "OS version not 10.9+ or OS version unrecognized"
      echo "$(/usr/bin/sw_vers -productVersion)"
      exit 5
    fi
  }

## successAlert
### display success message in a pop-up window
  successAlert () {
    /usr/bin/osascript -e "
    on run
    display dialog \"\" & return & \"Your FileVault key was successfully changed\" with title \"$windowTitle\" buttons {\"Close\"} default button 1 with icon POSIX file \"$brandIcon\"
    end run"
  }

## errorAlert
### display error message in a pop-up window
  errorAlert () {
    /usr/bin/osascript -e "
    on run
    display dialog \"FileVault key not changed\" & return & \"$result\" buttons {\"Cancel\", \"Try Again\"} default button 2 with title \"$windowTitle\" with icon POSIX file \"$brandIcon\"
    end run"

    # exit if user selected "Cancel" in pop-up window, else increment attempt counter
    if [ "$?" == "1" ]; then
      echo "User Canceled"
      exit 0
    else
      try=$(($try+1))
    fi
  }

## haltAlert
### display halt message in a pop-up window
  haltAlert () {
    /usr/bin/osascript -e "
    on run
    display dialog \"FileVault key not changed\" & return & \"$haltMsg\" buttons {\"Close\"} default button 1 with title \"$windowTitle\" with icon POSIX file \"$brandIcon\"
    end run
    "
  }

# MAIN
while true
do
  passwordPrompt
if [[ $result = *"Error"* ]]; then
  echo "Error changing key"
if [ $try -ge $maxTry ]; then
  haltAlert
  echo "Quitting.. too many failed attempts"
  exit 0
else
  echo $result
  errorAlert
fi
else
  echo "Successfully changed FV2 key"
  successAlert
  exit 0
fi
done
