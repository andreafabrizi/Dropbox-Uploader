#!/bin/bash
#
# Dropbox Uploader Script v0.8.1
#
# Copyright (C) 2010-2011 Andrea Fabrizi <andrea.fabrizi@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
# CHANGELOG:
#
# Version 0.8.1 - 31/08/2011
# Modified by Dawid Ferenczy (www.ferenczy.cz)
#  - added prompt for the Dropbox password from keyboard, if there is no password
#    hardcoded or given as script command line parameter (interactive mode)
#  - added INTERACTIVE_MODE variable - when set to 1 show CURL progress bar.
#    Set to 1 automatically when there is no password hardcoded or given as
#    parameter. Controls verbosity of CURL.
#
# Version 0.7.1 - 10/03/2011:
# - Minor bug fixes
# 
# Version 0.7 - 10/03/2011:
# - New command line interface
# - Code clean
#
# Version 0.6 - 11/01/2011:
# - Fixed issue with spaces in file/forder name
#
# Version 0.5 - 04/01/2011:
# - Recursive directory upload
#
# Version 0.4 - 29/12/2010:
# - Now works on BSD and MAC
# - Interactive prompt for username and password
# - Speeded up the uploading process
# - Debug mode
#
# Version 0.3 - 18/11/2010:
# - Regex updated
#
# Version 0.2 - 04/09/2010:
# - Removed dependencies from tempfile
# - Code clean
#
# Version 0.1 - 23/08/2010:
# - Initial release
#

#DROPBOX ACCOUNT
#For security reasons, it is not recommended to modify this script
#to hardcode a login and password.  However, this can be done if
#automation is necessary.
LOGIN_EMAIL=""
LOGIN_PASSWD=""

#Set to 1 to enable DEBUG mode
DEBUG=0

#Set to 1 to enable VERBOSE mode (-v option)
VERBOSE=0

#If set to 1 the script terminate if an upload error occurs
END_ON_UPLOAD_ERROR=0

#Set to 1 to skip the initial login page loading (Speed up the uploading process).
#Set to 0 if you experience problems uploading the files.
SKIP_LOADING_LOGIN_PAGE=1

#Don't edit these...
LOGIN_URL="https://www.dropbox.com/login"
HOME_URL="https://www.dropbox.com/home"
UPLOAD_URL="https://dl-web.dropbox.com/upload"
COOKIE_FILE="/tmp/du_cookie_$RANDOM"
RESPONSE_FILE="/tmp/du_resp_$RANDOM"
BIN_DEPS="curl sed grep tr pwd"
VERSION="0.8.1"

#Set to 1 to show CURL progress bar. Sets automatically to 1 when there is no password
#hardcoded or given as parameter. Controls verbosity of CURL.
INTERACTIVE_MODE=0

if [ $DEBUG -ne 0 ]; then
    set -x
    COOKIE_FILE="/tmp/du_cookie_debug"
    RESPONSE_FILE="/tmp/du_resp_debug"
fi

#Print verbose information depend on $VERBOSE variable
function print
{
    if [ $VERBOSE -eq 1 ]; then
	    echo -ne "$1";
    fi
}

#Remove temporary files
function remove_temp_files
{
    if [ $DEBUG -eq 0 ]; then
        rm -fr $COOKIE_FILE
        rm -fr $RESPONSE_FILE
    fi
}

#Extract token from the specified form
# $1 = file path
# $2 = form action
function get_token
{
    TOKEN=$(cat $1 | tr -d '\n' | sed 's/.*<form action="'$2'"[^>]*>\s*<input type="hidden" name="t" value="\([a-z 0-9]*\)".*/\1/')
    echo $TOKEN
}

#Upload a single file to dropbox
# $1 = local file path
# $2 = remote destination folder
function dropbox_upload
{
    UPLOAD_FILE=$1
    DEST_FOLDER=$2

    print " > Uploading '$UPLOAD_FILE' to 'DROPBOX$DEST_FOLDER'..."
    curl -s -i -b $COOKIE_FILE -o $RESPONSE_FILE -F "plain=yes" -F "dest=$DEST_FOLDER" -F "t=$TOKEN" -F "file=@$UPLOAD_FILE"  "$UPLOAD_URL"
    grep "HTTP/1.1 302 FOUND" "$RESPONSE_FILE" > /dev/null

    if [ $? -ne 0 ]; then
        print " Failed!\n"
        if [ $END_ON_UPLOAD_ERROR -eq 1 ]; then
            remove_temp_files
            exit 1
        fi
    else
        print " OK\n"
    fi
}

#Recursively upload a directory structure
# $1 = remote destination folder
function dropbox_upload_dir
{
    for i in *; do

        if [ -f "$i" ]; then
            dropbox_upload "$i" "$1"
        fi

        if [ -d "$i" ]; then
            local OLD_PWD=$(pwd)
            cd "$i"
            dropbox_upload_dir "$1/$i"
            cd "$OLD_PWD"
        fi
    done
}


#Handles the keyboard interrupt (control-c)
function ctrl_c
{
    print "\n Bye ;)\n"
    remove_temp_files
    exit 1
}

#Trap keyboard interrupt (control-c)
trap ctrl_c SIGINT

#CHECK DEPENDENCIES
for i in $BIN_DEPS; do
    which $i > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "Error: Required file could not be found: $i"
        remove_temp_files
        exit 1
    fi
done

#USAGE
function usage() {
    echo -e "Dropbox Uploader v$VERSION"
    echo -e "Usage: $0 [OPTIONS]..."
    echo -e "\nOptions:"
    echo -e "\t-u [USERNAME] (required if not hardcoded)"
    echo -e "\t-p [PASSWORD] (required if not hardcoded)"
    echo -e "\t-f [FILE/FOLDER] (required)"
    echo -e "\t-d [REMOTE_FOLDER] (default: /)"
    echo -e "\t-v Verbose mode"

    remove_temp_files
}

# File variables
UPLOAD_FILE=""
DEST_FOLDER=""

optn=0;

while getopts "u:p:f:d:v" opt; do
    case $opt in
        u)
            LOGIN_EMAIL="$OPTARG"
            let optn++;;
        p)
            LOGIN_PASSWD="$OPTARG"
            let optn++;;
        f)
            UPLOAD_FILE="$OPTARG"
            let optn++;;
        d)
            DEST_FOLDER="$OPTARG"
            let optn++;;
        v)
            VERBOSE=1;;
        *)
            usage;
            exit 0;
    esac
done

# interactive mode - prompt for the Dropbox password, if not hardcoded or given as parameter
if [ "$LOGIN_PASSWD" == "" ]; then
	read -s -p "Password: " LOGIN_PASSWD
	echo
	INTERACTIVE_MODE=1
fi

if [ $INTERACTIVE_MODE == 1 ]; then
	CURL_PARAMETERS="--progress-bar"
else
	CURL_PARAMETERS="-s --show-error"
fi

if [ $optn -lt 1 ] || [ "$LOGIN_EMAIL" == "" ] || [ "$LOGIN_PASSWD" == "" ]; then
	usage;
	exit 1;
fi

if [ "$DEST_FOLDER" == "" ]; then
    DEST_FOLDER="/"
fi

print "Dropbox Uploader v$VERSION\n"

#CHECK FILE/DIR
if [ ! -r "$UPLOAD_FILE" ]; then
    echo -e "Error reading '$1'"
    remove_temp_files
    exit 1
fi

#LOAD LOGIN PAGE
if [ $SKIP_LOADING_LOGIN_PAGE -eq 0 ]; then
    print " > Loading Login Page..."
    curl -s -i -o "$RESPONSE_FILE" "$LOGIN_URL"

    if [ $? -ne 0 ]; then
        print " Failed!\n"
        remove_temp_files
        exit 1
    else
        print " OK\n"
    fi

    #GET TOKEN
    TOKEN=$(get_token "$RESPONSE_FILE" "\/login")
    #echo -e " > Token = $TOKEN"
    if [ "$TOKEN" == "" ]; then
        print " Failed to get Authentication token!\n"
        remove_temp_files
        exit 1
    fi
fi

#LOGIN
print " > Logging in..."
curl $CURL_PARAMETERS -i -c $COOKIE_FILE -o $RESPONSE_FILE --data "login_email=$LOGIN_EMAIL&login_password=$LOGIN_PASSWD&t=$TOKEN" "$LOGIN_URL"
grep "location: /home" $RESPONSE_FILE > /dev/null

if [ $? -ne 0 ]; then
    print " Failed!\n"
    remove_temp_files
    exit 1
else
    print " OK\n"
fi

#LOAD HOME
print " > Loading Home..."
curl -s -i -b "$COOKIE_FILE" -o "$RESPONSE_FILE" "$HOME_URL"

if [ $? -ne 0 ]; then
    print " Failed!\n"
    remove_temp_files
    exit 1
else
    print " OK\n"
fi

#GET TOKEN
TOKEN=$(get_token "$RESPONSE_FILE" "https:\/\/dl-web.dropbox.com\/upload")
#echo -e " > Token = $TOKEN"
if [ "$TOKEN" == "" ]; then
    print " Failed to get Upload token!\n"
    remove_temp_files
    exit 1
fi

#If it's a single file...
if [ -f "$UPLOAD_FILE" ]; then
    dropbox_upload "$UPLOAD_FILE" "$DEST_FOLDER"
fi

#If it's a directory...
if [ -d "$UPLOAD_FILE" ]; then
    OLD_PWD=$(pwd)
    cd "$UPLOAD_FILE"
    dropbox_upload_dir "$DEST_FOLDER"
    cd "$OLD_PWD"
fi


remove_temp_files