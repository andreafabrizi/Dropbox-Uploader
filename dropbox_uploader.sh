#!/bin/bash
#
# Dropbox Uploader Script v0.9.2
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
APP_CREATE_URL="https://www2.dropbox.com/developers/apps"
RESPONSE_FILE="/tmp/du_resp_$RANDOM"
BIN_DEPS="curl sed"
VERSION="0.9.2"

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
    echo -e "\t info   - Print some info about your Dropbox account"
    echo -e "\t unlink - Unlink this script from you Dropbox account"
    
    echo -en "\n"
    remove_temp_files
    exit 1
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

#CHECKING FOR AUTH FILE
if [ -f $CONFIG_FILE ]; then
      
    #Loading data...
    APPKEY=$(sed -n -e 's/APPKEY:\([a-z A-Z 0-9]*\)/\1/p' $CONFIG_FILE)
    APPSECRET=$(sed -n -e 's/APPSECRET:\([a-z A-Z 0-9]*\)/\1/p' $CONFIG_FILE)
    OAUTH_ACCESS_TOKEN_SECRET=$(sed -n -e 's/OAUTH_ACCESS_TOKEN_SECRET:\([a-z A-Z 0-9]*\)/\1/p' $CONFIG_FILE)
    OAUTH_ACCESS_TOKEN=$(sed -n -e 's/OAUTH_ACCESS_TOKEN:\([a-z A-Z 0-9]*\)/\1/p' $CONFIG_FILE)
    OAUTH_ACCESS_TOKEN_SECRET=$(sed -n -e 's/OAUTH_ACCESS_TOKEN_SECRET:\([a-z A-Z 0-9]*\)/\1/p' $CONFIG_FILE)

#NEW SETUP...
else

    echo -ne "\n This is the first time you run this script.\n"
    echo -ne " Please open this URL from your Browser, and access using your account:\n\n -> $APP_CREATE_URL\n"
    echo -ne "\n If you haven't already done, click \"Create an App\" and fill in the\n"
    echo -ne " form with the following data:\n\n"
    echo -ne "  App name: MyUploader$RANDOM$RANDOM\n"
    echo -ne "  Description: What do you want...\n"
    echo -ne "  Access level: Full Dropbox\n\n"
    echo -ne " Now, click on the \"Create\" button.\n\n"
    
    echo -ne " When your new App is successfully created, please insert the\n"
    echo -ne " App Key and App Secret:\n\n"

    #Getting the app key and secret from the user
    while (true); do
        
        echo -n " # App key: "
        read APPKEY

        echo -n " # App secret: "
        read APPSECRET

        echo -ne " > App key is $APPKEY and App secret is $APPSECRET, it's ok? [y/n]"
        read answer
        if [ "$answer" == "y" ]; then
            break;
        fi

    done

    #TOKEN REQUESTS
    echo -ne "\n > Token request... "
    time=$(utime)
    curl -k -s --show-error -i -o $RESPONSE_FILE --data "oauth_consumer_key=$APPKEY&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_REQUEST_TOKEN_URL"
    OAUTH_TOKEN_SECRET=$(sed -n -e 's/oauth_token_secret=\([a-z A-Z 0-9]*\).*/\1/p' "$RESPONSE_FILE")
    OAUTH_TOKEN=$(sed -n -e 's/.*oauth_token=\([a-z A-Z 0-9]*\)/\1/p' "$RESPONSE_FILE")

    if [ "$OAUTH_TOKEN" != "" -a "$OAUTH_TOKEN_SECRET" != "" ]; then
        echo -ne "OK\n"
    else
        echo -ne " FAILED\n\n Verify your App key and secret...\n\n"
        remove_temp_files
        exit 1
    fi

    while (true); do

        #USER AUTH
        echo -ne "\n Please visit this URL from your Browser, and allow Dropbox Uploader\n"
        echo -ne " to access your DropBox account:\n\n --> ${API_USER_AUTH_URL}?oauth_token=$OAUTH_TOKEN\n"
        echo -ne "\nPress enter when done...\n"
        read

        #API_ACCESS_TOKEN_URL
        echo -ne " > Access Token request... "
        time=$(utime)
        curl -k -s --show-error -i -o $RESPONSE_FILE --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_ACCESS_TOKEN_URL"
        OAUTH_ACCESS_TOKEN_SECRET=$(sed -n -e 's/oauth_token_secret=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_TOKEN=$(sed -n -e 's/.*oauth_token=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_UID=$(sed -n -e 's/.*uid=\([0-9]*\)/\1/p' "$RESPONSE_FILE")
        
        if [ "$OAUTH_ACCESS_TOKEN" != "" -a "$OAUTH_ACCESS_TOKEN_SECRET" != "" -a "$OAUTH_ACCESS_UID" != "" ]; then
            echo -ne "OK\n"
            
            #Saving data
            echo "APPKEY:$APPKEY" > $CONFIG_FILE
            echo "APPSECRET:$APPSECRET" >> $CONFIG_FILE
            echo "OAUTH_ACCESS_TOKEN:$OAUTH_ACCESS_TOKEN" >> $CONFIG_FILE
            echo "OAUTH_ACCESS_TOKEN_SECRET:$OAUTH_ACCESS_TOKEN_SECRET" >> $CONFIG_FILE
            
            echo -ne "\n Setup completed!\n"
            break
        else
            print " FAILED\n"
        fi

    done;
    
    remove_temp_files     
    exit 0
fi

COMMAND=$1

#CHECKING PARAMS VALUES
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

unlink)
    #Nothing to do...
    ;;
        
*)
    usage
    ;;
esac

################
#### START  ####
################

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


    unlink)

        echo -ne "\n Are you sure you want unlink this script from your Dropbox account? [y/n]"
        read answer
        if [ "$answer" == "y" ]; then
            echo -ne "Done!\n"
            rm -fr $CONFIG_FILE
        fi
        
        ;;
                
    *)
        usage
        ;;
        
esac

remove_temp_files

