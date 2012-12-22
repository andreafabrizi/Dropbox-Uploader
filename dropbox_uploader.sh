#!/usr/bin/env bash
#
# Dropbox Uploader
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

#Default configuration file
CONFIG_FILE=~/.dropbox_uploader

#If you are experiencing problems establishing SSL connection with the DropBox
#server, try to uncomment this option.
#Note: This option explicitly allows curl to perform "insecure" SSL connections and transfers.
#CURL_ACCEPT_CERTIFICATES="-k"

#Default chunk size in Mb for the upload process
#It is recommended to increase this value only if you have enough free space on your /tmp partition
#Lower values may increase the number of http requests
CHUNK_SIZE=4

#Set to 1 to enable DEBUG mode
DEBUG=0

#Set to 1 to enable VERBOSE mode
VERBOSE=1

#Curl location
#If not set, curl will be searched into the $PATH
#CURL_BIN="/usr/bin/curl"

#Temporary folder
TMP_DIR="/tmp"

#Don't edit these...
API_REQUEST_TOKEN_URL="https://api.dropbox.com/1/oauth/request_token"
API_USER_AUTH_URL="https://www2.dropbox.com/1/oauth/authorize"
API_ACCESS_TOKEN_URL="https://api.dropbox.com/1/oauth/access_token"
API_CHUNKED_UPLOAD_URL="https://api-content.dropbox.com/1/chunked_upload"
API_CHUNKED_UPLOAD_COMMIT_URL="https://api-content.dropbox.com/1/commit_chunked_upload"
API_UPLOAD_URL="https://api-content.dropbox.com/1/files_put"
API_DOWNLOAD_URL="https://api-content.dropbox.com/1/files"
API_DELETE_URL="https://api.dropbox.com/1/fileops/delete"
API_METADATA_URL="https://api.dropbox.com/1/metadata"
API_INFO_URL="https://api.dropbox.com/1/account/info"
APP_CREATE_URL="https://www2.dropbox.com/developers/apps"
RESPONSE_FILE="$TMP_DIR/du_resp_$RANDOM"
CHUNK_FILE="$TMP_DIR/du_chunk_$RANDOM"
BIN_DEPS="sed basename date grep stat dd"
VERSION="0.11.3"

umask 077

#Check the shell
if [ -z "$BASH_VERSION" ]; then
    echo -e "Error: this script requires BASH shell!"
    exit 1
fi 

if [ $DEBUG -ne 0 ]; then
    set -x
    RESPONSE_FILE="$TMP_DIR/du_resp_debug"
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
    echo $(date +%s)
}

#Remove temporary files
function remove_temp_files
{
    if [ $DEBUG -eq 0 ]; then
        rm -fr "$RESPONSE_FILE"
        rm -fr "$CHUNK_FILE"
    fi
}

#Return the file size in bytes
# generic GNU Linux: linux-gnu
# windows cygwin:    cygwin
# raspberry pi:      linux-gnueabihf
# macosx:            darwin10.0
# freebsd:           FreeBSD
function file_size
{
    #Generic Linux
    if [ "${OSTYPE:0:5}" == "linux" -o "$OSTYPE" == "cygwin" ]; then
        stat --format="%s" "$1"
        return
    #BSD or others OS
    else
        stat -f "%z" "$1"
        return
    fi
}

#USAGE
function usage() {
    echo -e "Dropbox Uploader v$VERSION"
    echo -e "Andrea Fabrizi - andrea.fabrizi@gmail.com\n"
    echo -e "Usage: $0 COMMAND [PARAMETERS]..."
    echo -e "\nCommands:"
    
    echo -e "\t upload   [LOCAL_FILE]  <REMOTE_FILE>"
    echo -e "\t download [REMOTE_FILE] <LOCAL_FILE>"
    echo -e "\t delete   [REMOTE_FILE]"
    echo -e "\t list     <REMOTE_DIR>"
    echo -e "\t info"
    echo -e "\t unlink"
    
    echo -en "\nFor more info and examples, please see the README file.\n\n"
    remove_temp_files
    exit 1
}

if [ -z "$CURL_BIN" ]; then
    BIN_DEPS="$BIN_DEPS curl"
    CURL_BIN="curl"   
fi

#DEPENDENCIES CHECK
for i in $BIN_DEPS; do
    which $i > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "Error: Required program could not be found: $i"
        remove_temp_files
        exit 1
    fi
done

#Simple file upload
#$1 = Local source file
#$2 = Remote destination file
function db_upload
{
    local FILE_SRC=$1
    local FILE_DST=$2
    
    #Show the progress bar during the file upload
    if [ $VERBOSE -eq 1 ]; then
        CURL_PARAMETERS="--progress-bar"
    else
        CURL_PARAMETERS="-s --show-error"
    fi
 
    print " > Uploading $FILE_SRC to $2... \n"  
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES $CURL_PARAMETERS -i --globoff -o "$RESPONSE_FILE" --upload-file "$FILE_SRC" "$API_UPLOAD_URL/$ACCESS_LEVEL/$FILE_DST?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM"
           
    #Check
    grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
    if [ $? -eq 0 ]; then
        print " > DONE\n"
    else
        print " > FAILED\n"
        print "   An error occurred requesting /upload\n"
        remove_temp_files
        exit 1
    fi   
}

#Chunked file upload
#$1 = Local source file
#$2 = Remote destination file  
function db_ckupload
{
    local FILE_SRC=$1
    local FILE_DST=$2
    
    print " > Uploading \"$FILE_SRC\" to \"$2\""  

    local FILE_SIZE=$(file_size "$FILE_SRC")
    local OFFSET=0
    local UPLOAD_ID=""
    local UPLOAD_ERROR=0

    #Uploading chunks...
    while ([ $OFFSET -ne $FILE_SIZE ]); do      
      
        let OFFSET_MB=$OFFSET/1024/1024
      
        #Create the chunk
        dd if="$FILE_SRC" of="$CHUNK_FILE" bs=1048576 skip=$OFFSET_MB count=$CHUNK_SIZE 2> /dev/null
        
        #Only for the first request these parameters are not included
        if [ $OFFSET -ne 0 ]; then
            CHUNK_PARAMS="upload_id=$UPLOAD_ID&offset=$OFFSET"
        fi
        
        #Uploading the chunk...
        time=$(utime)
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --upload-file "$CHUNK_FILE" "$API_CHUNKED_UPLOAD_URL?$CHUNK_PARAMS&oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM"

        #Check
        grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
        if [ $? -ne 0 ]; then
            print "*"
            let UPLOAD_ERROR=$UPLOAD_ERROR+1
            
            #On error, the upload is retried for max 3 times
            if [ $UPLOAD_ERROR -gt 2 ]; then
                print " > FAILED\n"
                print "   An error occurred requesting /chunked_upload\n"
                remove_temp_files
                exit 1
            fi
            
        else
            print "."
            UPLOAD_ERROR=0
            UPLOAD_ID=$(sed -n 's/.*"upload_id": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
            OFFSET=$(sed -n 's/.*"offset": *\([^}]*\).*/\1/p' "$RESPONSE_FILE")
        fi
        
    done
    
    UPLOAD_ERROR=0
      
    #Commit the upload
    while (true); do
    
        time=$(utime)
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "upload_id=$UPLOAD_ID&oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_CHUNKED_UPLOAD_COMMIT_URL/$ACCESS_LEVEL/$FILE_DST"

        #Check
        grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
        if [ $? -ne 0 ]; then
            print "*"
            let UPLOAD_ERROR=$UPLOAD_ERROR+1
            
            #On error, the commit is retried for max 3 times
            if [ $UPLOAD_ERROR -gt 2 ]; then
                print " > FAILED\n"
                print "   An error occurred requesting /commit_chunked_upload\n"
                remove_temp_files
                exit 1
            fi
            
        else
            print "."
            UPLOAD_ERROR=0
            break
        fi
        
    done
    
    print "\n > DONE\n"
}

#Returns the free space on DropBox in bytes
function db_free_quota()
{
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_INFO_URL"
    
    #Check
    grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
    if [ $? -eq 0 ]; then
           
        quota=$(sed -n 's/.*"quota": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        used=$(sed -n 's/.*"normal": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        let free_quota=$quota-$used
        echo $free_quota
        
    else
        #On error, a big free quota is returned, so if this function fails the upload will not be blocked...
        echo 1000000000000
    fi
}

#Simple file download
#$1 = Remote source file
#$2 = Local destination file  
function db_download
{
    local FILE_SRC=$1
    local FILE_DST=$2
    
    #Show the progress bar during the file download
    if [ $VERBOSE -eq 1 ]; then
        local CURL_PARAMETERS="--progress-bar"
    else
        local CURL_PARAMETERS="-s --show-error"
    fi
 
    print " > Downloading \"$1\" to \"$FILE_DST\"... \n"  
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES $CURL_PARAMETERS --globoff -D "$RESPONSE_FILE" -o "$FILE_DST" "$API_DOWNLOAD_URL/$ACCESS_LEVEL/$FILE_SRC?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM"
           
    #Check
    grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
    if [ $? -eq 0 ]; then
        print " > DONE\n"
    else
        print " > FAILED\n"
        print "   If the problem persists, try to unlink this script from your\n"
        print "   Dropbox account, then setup again ($0 unlink).\n"
        rm -fr "$FILE_DST"
        remove_temp_files
        exit 1
    fi
         
}

#Pints account info
function db_account_info
{    
    print "Dropbox Uploader v$VERSION\n\n"
    print " > Getting info... \n"  
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_INFO_URL"
    
    #Check
    grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
    if [ $? -eq 0 ]; then
    
        name=$(sed -n 's/.*"display_name": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo -e "\nName:\t$name"
        
        uid=$(sed -n 's/.*"uid": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        echo -e "UID:\t$uid"
        
        email=$(sed -n 's/.*"email": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo -e "Email:\t$email"
        
        quota=$(sed -n 's/.*"quota": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        let quota_mb=$quota/1024/1024
        echo -e "Quota:\t$quota_mb Mb"
        
        used=$(sed -n 's/.*"normal": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        let used_mb=$used/1024/1024
        echo -e "Used:\t$used_mb Mb"

        let free_mb=($quota-$used)/1024/1024
        echo -e "Free:\t$free_mb Mb"
                
        echo ""
        
    else
        print " > FAILED\n"
        print "   If the problem persists, try to unlink this script from your\n"
        print "   Dropbox account, then setup again ($0 unlink).\n"
        remove_temp_files
        exit 1
    fi

}

#Account unlink
function db_unlink
{
    echo -ne "\n Are you sure you want unlink this script from your Dropbox account? [y/n]"
    read answer
    if [ "$answer" == "y" ]; then
        rm -fr "$CONFIG_FILE"
        echo -ne "Done!\n"
    fi       
}

#Delete a remote file
#$1 = Remote file to delete
function db_delete
{
    local FILE_DST=$1
       
    print " > Deleting \"$1\"... "  
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM&root=$ACCESS_LEVEL&path=$FILE_DST" "$API_DELETE_URL"

    #Check
    grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
    if [ $? -eq 0 ]; then
        print "DONE\n"
    else    
        print "FAILED\n"
        remove_temp_files
        exit 1
    fi       
}

#List remote directory
#$1 = Remote directory
function db_list
{
    local DIR_DST=$1
        
    print " > Listing \"$1\"... "  
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_METADATA_URL/$ACCESS_LEVEL/$DIR_DST?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM"
   
    #Check
    grep "HTTP/1.1 200 OK" "$RESPONSE_FILE" > /dev/null
    if [ $? -eq 0 ]; then
        
        local IS_DIR=$(sed -n 's/^\(.*\)\"contents":.\[.*/\1/p' "$RESPONSE_FILE")
                   
        #It's a directory
        if [ ! -z "$IS_DIR" ]; then
        
            print "DONE\n"
        
            #Extracting directory content [...]
            #and replacing "}, {" with "}\n{"
            #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
            local DIR_CONTENT=$(sed -n 's/.*: \[{\(.*\)/\1/p' "$RESPONSE_FILE" | sed 's/}, *{/}\
{/g')
            
            #Extracing files and subfolders
            echo "$DIR_CONTENT" | sed -n 's/.*"path": *"\([^"]*\)",.*"is_dir": *\([^"]*\),.*/\1:\2/p' > $RESPONSE_FILE
            
            #For each line...
            while read -r line; do
            
                local FILE=${line%:*}
                FILE=${FILE##*/}
                local TYPE=${line#*:}
                
                if [ "$TYPE" == "false" ]; then
                    printf " [F] $FILE\n"
                else
                    printf " [D] $FILE\n"
                fi
            done < $RESPONSE_FILE
        
        #It's a file
        else
            print "FAILED $DIR_DST is not a directory!\n"
            remove_temp_files
            exit 1
        fi
        
    else    
        print "FAILED\n"
        remove_temp_files
        exit 1
    fi
}

################
#### SETUP  ####
################

#CHECKING FOR AUTH FILE
if [ -f "$CONFIG_FILE" ]; then
      
    #Loading data...
    APPKEY=$(sed -n 's/APPKEY:\([a-z A-Z 0-9]*\)/\1/p' "$CONFIG_FILE")
    APPSECRET=$(sed -n 's/APPSECRET:\([a-z A-Z 0-9]*\)/\1/p' "$CONFIG_FILE")
    ACCESS_LEVEL=$(sed -n 's/ACCESS_LEVEL:\([A-Z]*\)/\1/p' "$CONFIG_FILE")
    OAUTH_ACCESS_TOKEN_SECRET=$(sed -n 's/OAUTH_ACCESS_TOKEN_SECRET:\([a-z A-Z 0-9]*\)/\1/p' "$CONFIG_FILE")
    OAUTH_ACCESS_TOKEN=$(sed -n 's/OAUTH_ACCESS_TOKEN:\([a-z A-Z 0-9]*\)/\1/p' "$CONFIG_FILE")
    
    #Checking the loaded data
    if [ -z "$APPKEY" -o -z "$APPSECRET" -o -z "$OAUTH_ACCESS_TOKEN_SECRET" -o -z "$OAUTH_ACCESS_TOKEN" ]; then
        echo -ne "Error loading data from $CONFIG_FILE...\n"
        echo -ne "It is recommended to run $0 unlink\n"
        remove_temp_files
        exit 1
    fi
    
    #Back compatibility with previous Dropbox Uploader versions
    if [ -z "$ACCESS_LEVEL" ]; then
        ACCESS_LEVEL="dropbox"
    fi

#NEW SETUP...
else

    echo -ne "\n This is the first time you run this script.\n"
    echo -ne " Please open this URL from your Browser, and access using your account:\n\n -> $APP_CREATE_URL\n"
    echo -ne "\n If you haven't already done, click \"Create an App\" and fill in the\n"
    echo -ne " form with the following data:\n\n"
    echo -ne "  App name: MyUploader$RANDOM$RANDOM\n"
    echo -ne "  Description: What do you want...\n"
    echo -ne "  Access level: App folder or Full Dropbox\n\n"
    echo -ne " Now, click on the \"Create\" button.\n\n"
    
    echo -ne " When your new App is successfully created, please type the\n"
    echo -ne " App Key, App Secret and the Access level:\n\n"

    #Getting the app key and secret from the user
    while (true); do
        
        echo -n " # App key: "
        read APPKEY

        echo -n " # App secret: "
        read APPSECRET

        echo -n " # Access level you have chosen, App folder or Full Dropbox [a/f]: "
        read ACCESS_LEVEL
        
        if [ "$ACCESS_LEVEL" == "a" ]; then
            ACCESS_LEVEL="sandbox"
            ACCESS_MSG="App Folder"
        else
            ACCESS_LEVEL="dropbox"
            ACCESS_MSG="Full Dropbox"
        fi
        
        echo -ne "\n > App key is $APPKEY, App secret is $APPSECRET and Access level is $ACCESS_MSG, it's ok? [y/n]"
        read answer
        if [ "$answer" == "y" ]; then
            break;
        fi

    done

    #TOKEN REQUESTS
    echo -ne "\n > Token request... "
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o $RESPONSE_FILE --data "oauth_consumer_key=$APPKEY&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_REQUEST_TOKEN_URL"
    OAUTH_TOKEN_SECRET=$(sed -n 's/oauth_token_secret=\([a-z A-Z 0-9]*\).*/\1/p' "$RESPONSE_FILE")
    OAUTH_TOKEN=$(sed -n 's/.*oauth_token=\([a-z A-Z 0-9]*\)/\1/p' "$RESPONSE_FILE")

    if [ -n "$OAUTH_TOKEN" -a -n "$OAUTH_TOKEN_SECRET" ]; then
        echo -ne "OK\n"
    else
        echo -ne " FAILED\n\n Please, check your App key and secret...\n\n"
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
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o $RESPONSE_FILE --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_ACCESS_TOKEN_URL"
        OAUTH_ACCESS_TOKEN_SECRET=$(sed -n 's/oauth_token_secret=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_TOKEN=$(sed -n 's/.*oauth_token=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_UID=$(sed -n 's/.*uid=\([0-9]*\)/\1/p' "$RESPONSE_FILE")
        
        if [ -n "$OAUTH_ACCESS_TOKEN" -a -n "$OAUTH_ACCESS_TOKEN_SECRET" -a -n "$OAUTH_ACCESS_UID" ]; then
            echo -ne "OK\n"
            
            #Saving data
            echo "APPKEY:$APPKEY" > "$CONFIG_FILE"
            echo "APPSECRET:$APPSECRET" >> "$CONFIG_FILE"
            echo "ACCESS_LEVEL:$ACCESS_LEVEL" >> "$CONFIG_FILE"
            echo "OAUTH_ACCESS_TOKEN:$OAUTH_ACCESS_TOKEN" >> "$CONFIG_FILE"
            echo "OAUTH_ACCESS_TOKEN_SECRET:$OAUTH_ACCESS_TOKEN_SECRET" >> "$CONFIG_FILE"
            
            echo -ne "\n Setup completed!\n"
            break
        else
            print " FAILED\n"
        fi

    done;
    
    remove_temp_files     
    exit 0
fi

################
#### START  ####
################

COMMAND=$1

#CHECKING PARAMS VALUES
case $COMMAND in

    upload)

        FILE_SRC=$2
        FILE_DST=$3

        #Checking FILE_SRC
        if [ ! -f "$FILE_SRC" ]; then
            echo -e "Error: Please specify a valid source file!"
            remove_temp_files
            exit 1
        fi
        
        #Checking FILE_DST
        if [ -z "$FILE_DST" ]; then
            FILE_DST=/$(basename "$FILE_SRC")
        fi
        
        #Checking file size
        FILE_SIZE=$(file_size "$FILE_SRC")
        
        #Checking the free quota
        FREE_QUOTA=$(db_free_quota)
        if [ $FILE_SIZE -gt $FREE_QUOTA ]; then
            let FREE_MB_QUOTA=$FREE_QUOTA/1024/1024
            echo -e "Error: You have no enough space on your DropBox!"
            echo -e "Free quota: $FREE_MB_QUOTA Mb"
            remove_temp_files
            exit 1
        fi
        
        if [ $FILE_SIZE -gt 157286000 ]; then
            #If the file is greater than 150Mb, the chunked_upload API will be used
            db_ckupload "$FILE_SRC" "$FILE_DST"
        else
            db_upload "$FILE_SRC" "$FILE_DST"
        fi
        
    ;;

    download)

        FILE_SRC=$2
        FILE_DST=$3    

        #Checking FILE_SRC
        if [ -z "$FILE_SRC" ]; then
            echo -e "Error: Please specify a valid source file!"
            remove_temp_files
            exit 1
        fi
        
        #Checking FILE_DST
        if [ -z "$FILE_DST" ]; then
            FILE_DST=$(basename "$FILE_SRC")
        fi
        
        db_download "$FILE_SRC" "$FILE_DST"
        
    ;;
        
    info)
    
        db_account_info
    
    ;;

    delete|remove)

        FILE_DST=$2    

        #Checking FILE_DST
        if [ -z "$FILE_DST" ]; then
            echo -e "Error: Please specify a valid destination file!"
            remove_temp_files
            exit 1
        fi

        db_delete "$FILE_DST"

    ;;

    list)

        DIR_DST=$2

        #Checking DIR_DST
        if [ -z "$DIR_DST" ]; then
            DIR_DST="/"
        fi
        
        db_list "$DIR_DST"

    ;;
        
    unlink)
    
        db_unlink    
    
    ;;
            
    *)
    
        usage
    
    ;;

esac 
   
remove_temp_files
exit 0
