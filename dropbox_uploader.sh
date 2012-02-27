#!/bin/bash
#
# Dropbox Uploader Script v0.9
#
# Copyright (C) 2010-2012 Andrea Fabrizi <andrea.fabrizi@gmail.com>
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
#Set to 1 to enable DEBUG mode
DEBUG=0

#Set to 1 to enable VERBOSE mode
VERBOSE=1

#Default configuration file
CONFIG_FILE=~/.dropbox_uploader

#Don't edit these...
API_REQUEST_TOKEN_URL="https://api.dropbox.com/1/oauth/request_token"
API_USER_AUTH_URL="https://www2.dropbox.com/1/oauth/authorize"
API_ACCESS_TOKEN_URL="https://api.dropbox.com/1/oauth/access_token"
API_UPLOAD_URL="https://api-content.dropbox.com/1/files_put/dropbox"
API_INFO_URL="https://api.dropbox.com/1/account/info"
RESPONSE_FILE="/tmp/du_resp_$RANDOM"
APPKEY="7s6g8l8snnbd676"
APPSECRET="xn6it23jky8q5y1"
BIN_DEPS="curl sed"
VERSION="0.9"

umask 077

if [ $DEBUG -ne 0 ]; then
    set -x
    RESPONSE_FILE="/tmp/du_resp_debug"
fi

#Print verbose information depends on $VERBOSE variable
function print
{
    if [ $VERBOSE -eq 1 ]; then
	    echo -ne "$1";
    fi
}

#Returns unix timestamp
function utime
{
    return $(date +%s)
}

#Remove temporary files
function remove_temp_files
{
    if [ $DEBUG -eq 0 ]; then
        rm -fr $RESPONSE_FILE
    fi
}

#Replace spaces
function urlencode
{
    str=$1
    echo ${str// /%20}
}

#USAGE
function usage() {
    echo -e "Dropbox Uploader v$VERSION"
    echo -e "Andrea Fabrizi - andrea.fabrizi@gmail.com\n"
    echo -e "Usage: $0 COMMAND [PARAMETERS]..."
    echo -e "\nCommands:"
    echo -e "\t upload [LOCAL_FILE] [DESTINATION_FILE]"
    echo -e "\t info"

    remove_temp_files
}

#CHECK DEPENDENCIES
for i in $BIN_DEPS; do
    which $i > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "Error: Required file could not be found: $i"
        remove_temp_files
        exit 1
    fi
done

#CHECK PARAMS
COMMAND=$1

case $COMMAND in

upload)

    FILE_SRC=$2
    FILE_DST=$(urlencode "$3")

    #Checking FILE_SRC
    if [ ! -f "$FILE_SRC" ]; then
        echo -e "Please specify a valid source file!"
        remove_temp_files
        exit 1
    fi
    
    #Checking FILE_DST
    if [ -z "$FILE_DST" ]; then
        FILE_DST=$(basename "$FILE_SRC")
    fi    
    
    ;;

info)
    #Nothing to do...
    ;;
    
*)
    usage
    exit 1
    ;;
esac

################
#### START  ####
################

print " > Looking for auth file... "

#CONFIG FILE FOUND
if [ -f $CONFIG_FILE ]; then
    
    print "FOUND\n"
    
    #Loading tokens...
    OAUTH_ACCESS_TOKEN=$(sed -n -e 's/OAUTH_ACCESS_TOKEN:\([a-z A-Z 0-9]*\)/\1/p' $CONFIG_FILE)
    OAUTH_ACCESS_TOKEN_SECRET=$(sed -n -e 's/OAUTH_ACCESS_TOKEN_SECRET:\([a-z A-Z 0-9]*\)/\1/p' $CONFIG_FILE)

#CONFIG FILE NOT FOUND
else

    print "NOT FOUND\n"

    #TOKEN REQUESTS
    print " > Token request... "
    time=$(utime)
    curl -k -s --show-error -i -o $RESPONSE_FILE --data "oauth_consumer_key=$APPKEY&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_REQUEST_TOKEN_URL"
    OAUTH_TOKEN_SECRET=$(sed -n -e 's/oauth_token_secret=\([a-z A-Z 0-9]*\).*/\1/p' "$RESPONSE_FILE")
    OAUTH_TOKEN=$(sed -n -e 's/.*oauth_token=\([a-z A-Z 0-9]*\)/\1/p' "$RESPONSE_FILE")

    if [ "$OAUTH_TOKEN" != "" -a "$OAUTH_TOKEN_SECRET" != "" ]; then
        print "OK\n"
    else
        print " Failed!\n"
        remove_temp_files
        exit 1
    fi

    while (true); do

        #USER AUTH
        print "\n This is the first time you run this script.\n"
        print " Please visit this URL from your Browser, and allow Dropbox Uploader to access your DropBox account:\n ${API_USER_AUTH_URL}?oauth_token=$OAUTH_TOKEN\n"
        print "\nPress enter when done...\n"
        read

        #API_ACCESS_TOKEN_URL
        print " > Access Token request... "
        time=$(utime)
        curl -k -s --show-error -i -o $RESPONSE_FILE --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_ACCESS_TOKEN_URL"
        OAUTH_ACCESS_TOKEN_SECRET=$(sed -n -e 's/oauth_token_secret=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_TOKEN=$(sed -n -e 's/.*oauth_token=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_UID=$(sed -n -e 's/.*uid=\([0-9]*\)/\1/p' "$RESPONSE_FILE")
        
        if [ "$OAUTH_ACCESS_TOKEN" != "" -a "$OAUTH_ACCESS_TOKEN_SECRET" != "" -a "$OAUTH_ACCESS_UID" != "" ]; then
            print "OK\n"
            
            #Saving TOKENS
            echo "OAUTH_ACCESS_TOKEN:$OAUTH_ACCESS_TOKEN" > $CONFIG_FILE
            echo "OAUTH_ACCESS_TOKEN_SECRET:$OAUTH_ACCESS_TOKEN_SECRET" >> $CONFIG_FILE
            
            break
        else
            print " Failed!\n"
        fi

    done;

fi


#COMMAND EXECUTION
case "$COMMAND" in

    upload)

        #Show the progress bar during the file upload
        if [ $VERBOSE -eq 1 ]; then
	        CURL_PARAMETERS="--progress-bar"
        else
	        CURL_PARAMETERS="-s --show-error"
        fi
     
        print " > Uploading $FILE_SRC to $FILE_DST... \n"  
        time=$(utime)
        curl $CURL_PARAMETERS -k -i -o "$RESPONSE_FILE" --upload-file "$FILE_SRC" "$API_UPLOAD_URL/$FILE_DST?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM"
        
        #Check
        grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
        if [ $? -eq 0 ]; then
            print " DONE\n"
        else
            print " ERROR\n"
        fi
        
        ;;


    info)
     
        CURL_PARAMETERS="-s --show-error"
        print " > Getting info... \n"  
        time=$(utime)
        curl $CURL_PARAMETERS -k -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_INFO_URL"
        cat "$RESPONSE_FILE" | grep "{"
        
        ;;
        
    *)
        usage
        exit 1
        ;;
        
esac

remove_temp_files

