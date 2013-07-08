#!/usr/bin/env bash
#
# Dropbox Uploader
#
# Copyright (C) 2010-2013 Andrea Fabrizi <andrea.fabrizi@gmail.com>
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

#Default chunk size in Mb for the upload process
#It is recommended to increase this value only if you have enough free space on your /tmp partition
#Lower values may increase the number of http requests
CHUNK_SIZE=4

#Curl location
#If not set, curl will be searched into the $PATH
#CURL_BIN="/usr/bin/curl"

#Default values
TMP_DIR="/tmp"
DEBUG=0
QUIET=0
SHOW_PROGRESSBAR=0

#Don't edit these...
API_REQUEST_TOKEN_URL="https://api.dropbox.com/1/oauth/request_token"
API_USER_AUTH_URL="https://www2.dropbox.com/1/oauth/authorize"
API_ACCESS_TOKEN_URL="https://api.dropbox.com/1/oauth/access_token"
API_CHUNKED_UPLOAD_URL="https://api-content.dropbox.com/1/chunked_upload"
API_CHUNKED_UPLOAD_COMMIT_URL="https://api-content.dropbox.com/1/commit_chunked_upload"
API_UPLOAD_URL="https://api-content.dropbox.com/1/files_put"
API_DOWNLOAD_URL="https://api-content.dropbox.com/1/files"
API_DELETE_URL="https://api.dropbox.com/1/fileops/delete"
API_MOVE_URL="https://api.dropbox.com/1/fileops/move"
API_METADATA_URL="https://api.dropbox.com/1/metadata"
API_INFO_URL="https://api.dropbox.com/1/account/info"
API_MKDIR_URL="https://api.dropbox.com/1/fileops/create_folder"
API_SHARES_URL="https://api.dropbox.com/1/shares"
APP_CREATE_URL="https://www2.dropbox.com/developers/apps"
RESPONSE_FILE="$TMP_DIR/du_resp_$RANDOM"
CHUNK_FILE="$TMP_DIR/du_chunk_$RANDOM"
BIN_DEPS="sed basename date grep stat dd printf mkdir"
VERSION="0.11.9"

umask 077

#Check the shell
if [ -z "$BASH_VERSION" ]; then
    echo -e "Error: this script requires the BASH shell!"
    exit 1
fi

#Look for optional config file parameter
while getopts ":qpkdf:" opt; do
    case $opt in

    f)
      CONFIG_FILE=$OPTARG
    ;;

    d)
      DEBUG=1
    ;;

    q)
      QUIET=1
    ;;

    p)
      SHOW_PROGRESSBAR=1
    ;;
    
    k)
      CURL_ACCEPT_CERTIFICATES="-k"
    ;;

    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
    ;;

    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
    ;;

  esac
done

if [ $DEBUG -ne 0 ]; then
    set -x
    RESPONSE_FILE="$TMP_DIR/du_resp_debug"
fi

#Print the message based on $QUIET variable
function print
{
    if [ $QUIET -eq 0 ]; then
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

#Returns the file size in bytes
# generic GNU Linux: linux-gnu
# windows cygwin:    cygwin
# raspberry pi:      linux-gnueabihf
# macosx:            darwin10.0
# freebsd:           FreeBSD
# qnap:              linux-gnueabi
# iOS:               darwin9
function file_size
{
    #Some embedded linux devices
    if [ "$OSTYPE" == "linux-gnueabi" -o "$OSTYPE" == "linux-gnu" ]; then
        stat -c "%s" "$1"
        return

    #Generic Unix
    elif [ "${OSTYPE:0:5}" == "linux" -o "$OSTYPE" == "cygwin" -o "${OSTYPE:0:7}" == "solaris" -o "${OSTYPE}" == "darwin9" ]; then
        stat --format="%s" "$1"
        return

    #BSD or others OS
    else
        stat -f "%z" "$1"
        return
    fi
}

#Usage
function usage
{
    echo -e "Dropbox Uploader v$VERSION"
    echo -e "Andrea Fabrizi - andrea.fabrizi@gmail.com\n"
    echo -e "Usage: $0 COMMAND [PARAMETERS]..."
    echo -e "\nCommands:"

    echo -e "\t upload   [LOCAL_FILE/DIR]  <REMOTE_FILE/DIR>"
    echo -e "\t download [REMOTE_FILE/DIR] <LOCAL_FILE/DIR>"
    echo -e "\t delete   [REMOTE_FILE/DIR]"
    echo -e "\t move     [REMOTE_FILE/DIR] [REMOTE_FILE/DIR]"
    echo -e "\t mkdir    [REMOTE_DIR]"
    echo -e "\t list     <REMOTE_DIR>"
    echo -e "\t share    [REMOTE_FILE]"
    echo -e "\t info"
    echo -e "\t unlink"

    echo -e "\nOptional parameters:"
    echo -e "\t-f [FILENAME] Load the configuration file from a specific file"
    echo -e "\t-d            Enable DEBUG mode"
    echo -e "\t-q            Quiet mode. Don't show messages"
    echo -e "\t-p            Show cURL progress meter"
    echo -e "\t-k            Doesn't check for SSL certificates (insecure)"

    echo -en "\nFor more info and examples, please see the README file.\n\n"
    remove_temp_files
    exit 1
}

#Check the curl exit code
function check_curl_status
{
    CODE=$?

    case $CODE in

        #OK
        0)
            return
        ;;

        #Proxy error
        5)
            echo ""
            echo "Error: Couldn't resolve proxy. The given proxy host could not be resolved."

            remove_temp_files
            exit 1
        ;;

        #Missing CA certificates
        60|58)
            echo ""
            echo "Error: cURL is not able to performs peer SSL certificate verification."
            echo "Please, install the default ca-certificates bundle."
            echo "To do this in a Debian/Ubuntu based system, try:"
            echo "  sudo apt-get install ca-certificates"
            echo ""
            echo "If the problem persists, try to use the -k option (insecure)."
            echo ""

            remove_temp_files
            exit 1
        ;;
    esac
}

if [ -z "$CURL_BIN" ]; then
    BIN_DEPS="$BIN_DEPS curl"
    CURL_BIN="curl"
fi

#Dependencies check
which $BIN_DEPS > /dev/null
if [ $? -ne 0 ]; then
    for i in $BIN_DEPS; do
        which $i > /dev/null ||
            NOT_FOUND="$i $NOT_FOUND"
    done
    echo -e "Error: Required program could not be found: $NOT_FOUND"
    remove_temp_files
    exit 1
fi

#Urlencode
function urlencode
{
    local string="${1}"
    local strlen=${#string}
    local encoded=""

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done

    echo "$encoded"
}

#Check if it's a file or directory
#Returns FILE/DIR/ERR
function db_stat
{
    local FILE=$(urlencode "$1")

    #Checking if it's a file or a directory
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_METADATA_URL/$ACCESS_LEVEL/$FILE?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" 2> /dev/null
    check_curl_status

    #Even if the file/dir has been deleted from DropBox we receive a 200 OK response
    #So we must check if the file exists or if it has been deleted
    local IS_DELETED=$(sed -n 's/.*"is_deleted":.\([^,]*\).*/\1/p' "$RESPONSE_FILE")

    #Exits...
    grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"
    if [ $? -eq 0 -a "$IS_DELETED" != "true" ]; then

        local IS_DIR=$(sed -n 's/^\(.*\)\"contents":.\[.*/\1/p' "$RESPONSE_FILE")

        #It's a directory
        if [ ! -z "$IS_DIR" ]; then
            echo "DIR"
        #It's a file
        else
            echo "FILE"
        fi

    #Doesn't exists
    else
        echo "ERR"
    fi
}

#Generic upload wrapper around db_upload_file and db_upload_dir functions
#$1 = Local source file/dir
#$2 = Remote destination file/dir
function db_upload
{
    local SRC="$1"
    local DST="$2"

    #Checking if DST it's a folder or if it doesn' exists (in this case will be the destination name)
    TYPE=$(db_stat "$DST")
    if [ "$TYPE" == "DIR" ]; then
        local filename=$(basename "$SRC")
        DST="$DST/$filename"
    fi

    #It's a file
    if [ -f "$SRC" ]; then
        db_upload_file "$SRC" "$DST"

    #It's a directory
    elif [ -d "$SRC" ]; then
        db_upload_dir "$SRC" "$DST"

    #Unsupported object...
    else
        print " > Skipping not regular file '$SRC'"
    fi
}

#Generic upload wrapper around db_chunked_upload_file and db_simple_upload_file
#The final upload function will be choosen based on the file size
#$1 = Local source file
#$2 = Remote destination file
function db_upload_file
{
    local FILE_SRC="$1"
    local FILE_DST="$2"

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
        db_chunked_upload_file "$FILE_SRC" "$FILE_DST"
    else
        db_simple_upload_file "$FILE_SRC" "$FILE_DST"
    fi
}

#Simple file upload
#$1 = Local source file
#$2 = Remote destination file
function db_simple_upload_file
{
    local FILE_SRC="$1"
    local FILE_DST=$(urlencode "$2")
    
    if [ $SHOW_PROGRESSBAR -eq 1 -a $QUIET -eq 0 ]; then
        CURL_PARAMETERS="--progress-bar"
        LINE_CR="\n"
    else
        CURL_PARAMETERS="-s"
        LINE_CR=""
    fi

    print " > Uploading \"$FILE_SRC\" to \"$2\"... $LINE_CR"
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES $CURL_PARAMETERS -i --globoff -o "$RESPONSE_FILE" --upload-file "$FILE_SRC" "$API_UPLOAD_URL/$ACCESS_LEVEL/$FILE_DST?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM"
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        print "An error occurred requesting /upload\n"
        remove_temp_files
        exit 1
    fi
}

#Chunked file upload
#$1 = Local source file
#$2 = Remote destination file
function db_chunked_upload_file
{
    local FILE_SRC="$1"
    local FILE_DST=$(urlencode "$2")

    print " > Uploading \"$FILE_SRC\" to \"$2\" z"

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
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --upload-file "$CHUNK_FILE" "$API_CHUNKED_UPLOAD_URL?$CHUNK_PARAMS&oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" 2> /dev/null
        check_curl_status

        #Check
        if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
            print "."
            UPLOAD_ERROR=0
            UPLOAD_ID=$(sed -n 's/.*"upload_id": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
            OFFSET=$(sed -n 's/.*"offset": *\([^}]*\).*/\1/p' "$RESPONSE_FILE") 
        else
            print "*"
            let UPLOAD_ERROR=$UPLOAD_ERROR+1

            #On error, the upload is retried for max 3 times
            if [ $UPLOAD_ERROR -gt 2 ]; then
                print " FAILED\n"
                print "An error occurred requesting /chunked_upload\n"
                remove_temp_files
                exit 1
            fi
        fi

    done

    UPLOAD_ERROR=0

    #Commit the upload
    while (true); do

        time=$(utime)
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "upload_id=$UPLOAD_ID&oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_CHUNKED_UPLOAD_COMMIT_URL/$ACCESS_LEVEL/$FILE_DST" 2> /dev/null
        check_curl_status

        #Check
        if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
            print "."
            UPLOAD_ERROR=0
            break
        else
            print "*"
            let UPLOAD_ERROR=$UPLOAD_ERROR+1

            #On error, the commit is retried for max 3 times
            if [ $UPLOAD_ERROR -gt 2 ]; then
                print " FAILED\n"
                print "An error occurred requesting /commit_chunked_upload\n"
                remove_temp_files
                exit 1
            fi
        fi

    done

    print " DONE\n"
}

#Directory upload
#$1 = Local source dir
#$2 = Remote destination dir
function db_upload_dir
{
    local DIR_SRC="$1"
    local DIR_DST="$2"

    #Creatig remote directory
    db_mkdir "$DIR_DST"

    for file in "$DIR_SRC/"*; do

        basefile=$(basename "$file")
        db_upload "$file" "$DIR_DST/$basefile"

    done
}

#Returns the free space on DropBox in bytes
function db_free_quota
{
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_INFO_URL" 2> /dev/null
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

        quota=$(sed -n 's/.*"quota": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        used=$(sed -n 's/.*"normal": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
        let free_quota=$quota-$used
        echo $free_quota

    else
        #On error, a big free quota is returned, so if this function fails the upload will not be blocked...
        echo 1000000000000
    fi
}

#Generic download wrapper
#$1 = Remote source file/dir
#$2 = Local destination file/dir
function db_download
{
    local SRC="$1"
    local DST="$2"

    TYPE=$(db_stat "$SRC")

    #It's a directory
    if [ $TYPE == "DIR" ]; then

        #If the DST folder is not specified, I assume that is the current directory
        if [ -z "$DST" ]; then
            DST="."
        fi

        #Checking if the destination directory exists
        if [ ! -d "$DST" ]; then
            local basedir=""
        else
            local basedir=$(basename "$SRC")
        fi

        print " > Downloading \"$1\" to \"$DST/$basedir\"... \n"
        print " > Creating local directory \"$DST/$basedir\"... "
        mkdir -p "$DST/$basedir"

        #Check
        if [ $? -eq 0 ]; then
            print "DONE\n"
        else
            print "FAILED\n"
            remove_temp_files
            exit 1
        fi

        #Extracting directory content [...]
        #and replacing "}, {" with "}\n{"
        #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
        local DIR_CONTENT=$(sed -n 's/.*: \[{\(.*\)/\1/p' "$RESPONSE_FILE" | sed 's/}, *{/}\
{/g')

        #Extracing files and subfolders
        TMP_DIR_CONTENT_FILE="${RESPONSE_FILE}_$RANDOM"
        echo "$DIR_CONTENT" | sed -n 's/.*"path": *"\([^"]*\)",.*"is_dir": *\([^"]*\),.*/\1:\2/p' > $TMP_DIR_CONTENT_FILE

        #For each line...
        while read -r line; do

            local FILE=${line%:*}
            FILE=${FILE##*/}
            local TYPE=${line#*:}

            if [ "$TYPE" == "false" ]; then
                db_download_file "$SRC/$FILE" "$DST/$basedir/$FILE"
            else
                db_download "$SRC/$FILE" "$DST/$basedir"
            fi

        done < $TMP_DIR_CONTENT_FILE

        rm -fr $TMP_DIR_CONTENT_FILE

    #It's a file
    elif [ $TYPE == "FILE" ]; then

        #Checking DST
        if [ -z "$DST" ]; then
            DST=$(basename "$SRC")
        fi

        #If the destination is a directory, the file will be download into
        if [ -d "$DST" ]; then
            DST="$DST/$SRC"
        fi

        db_download_file "$SRC" "$DST"
    
    #Doesn't exists
    else
        print "Error: No such file or directory: $SRC\n"
        remove_temp_files
        exit 1
    fi
}

#Simple file download
#$1 = Remote source file
#$2 = Local destination file
function db_download_file
{
    local FILE_SRC=$(urlencode "$1")
    local FILE_DST=$2

    if [ $SHOW_PROGRESSBAR -eq 1 -a $QUIET -eq 0 ]; then
        CURL_PARAMETERS="--progress-bar"
        LINE_CR="\n"
    else
        CURL_PARAMETERS="-s"
        LINE_CR=""
    fi

    print " > Downloading \"$1\" to \"$FILE_DST\"... $LINE_CR"
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES $CURL_PARAMETERS --globoff -D "$RESPONSE_FILE" -o "$FILE_DST" "$API_DOWNLOAD_URL/$ACCESS_LEVEL/$FILE_SRC?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM"
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        rm -fr "$FILE_DST"
        remove_temp_files
        exit 1
    fi
}

#Prints account info
function db_account_info
{
    print "Dropbox Uploader v$VERSION\n\n"
    print " > Getting info... "
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_INFO_URL" 2> /dev/null
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

        name=$(sed -n 's/.*"display_name": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo -e "\n\nName:\t$name"

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
        print "FAILED\n"
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
        echo -ne "DONE\n"
    fi
}

#Delete a remote file
#$1 = Remote file to delete
function db_delete
{
    local FILE_DST=$(urlencode "$1")

    print " > Deleting \"$1\"... "
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM&root=$ACCESS_LEVEL&path=$FILE_DST" "$API_DELETE_URL" 2> /dev/null
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        remove_temp_files
        exit 1
    fi
}

#Move/Rename a remote file
#$1 = Remote file to rename or move
#$2 = New file name or location
function db_move
{
    local FILE_SRC="$1"
    local FILE_DST="$2"

    TYPE=$(db_stat "$FILE_DST")

    #If the destination it's a directory, the source will be moved into it
    if [ "$TYPE" == "DIR" ]; then
        local filename=$(basename "$FILE_SRC")
        FILE_DST="$FILE_DST/$filename"
    fi

    local FILE_SRC=$(urlencode "$FILE_SRC")
    local FILE_DST=$(urlencode "$FILE_DST")

    print " > Moving \"$1\" to \"$2\" ... "
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM&root=$ACCESS_LEVEL&from_path=$FILE_SRC&to_path=$FILE_DST" "$API_MOVE_URL" 2> /dev/null
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        remove_temp_files
        exit 1
    fi
}

#Create a new directory
#$1 = Remote directory to create
function db_mkdir
{
    local DIR_DST=$(urlencode "$1")

    print " > Creating Directory \"$1\"... "
    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM&root=$ACCESS_LEVEL&path=$DIR_DST" "$API_MKDIR_URL" 2> /dev/null
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    elif grep -q "HTTP/1.1 403 Forbidden" "$RESPONSE_FILE"; then
        print "ALREADY EXISTS\n"
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
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_METADATA_URL/$ACCESS_LEVEL/$DIR_DST?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" 2> /dev/null
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

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

#Share remote file
#$1 = Remote file
function db_share
{
    local FILE_DST=$(urlencode "$1")

    time=$(utime)
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_SHARES_URL/$ACCESS_LEVEL/$FILE_DST?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM&short_url=false" 2> /dev/null
    check_curl_status

    #Check
    if grep -q "HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print " > Share link: "
        echo $(sed -n 's/.*"url": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
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

    #Loading data... and change old format config if necesary.
    source "$CONFIG_FILE" 2>/dev/null || {
        sed -i 's/:/=/' "$CONFIG_FILE" && source "$CONFIG_FILE" 2>/dev/null
    }

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
    echo -ne "  App type: Core\n"
    echo -ne "  Permission type: App folder or Full Dropbox\n\n"
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
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o $RESPONSE_FILE --data "oauth_consumer_key=$APPKEY&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_REQUEST_TOKEN_URL" 2> /dev/null
    check_curl_status
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
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o $RESPONSE_FILE --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_TOKEN_SECRET&oauth_timestamp=$time&oauth_nonce=$RANDOM" "$API_ACCESS_TOKEN_URL" 2> /dev/null
        check_curl_status
        OAUTH_ACCESS_TOKEN_SECRET=$(sed -n 's/oauth_token_secret=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_TOKEN=$(sed -n 's/.*oauth_token=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_UID=$(sed -n 's/.*uid=\([0-9]*\)/\1/p' "$RESPONSE_FILE")

        if [ -n "$OAUTH_ACCESS_TOKEN" -a -n "$OAUTH_ACCESS_TOKEN_SECRET" -a -n "$OAUTH_ACCESS_UID" ]; then
            echo -ne "OK\n"

            #Saving data in new format, compatible with source command.
            echo "APPKEY=$APPKEY" > "$CONFIG_FILE"
            echo "APPSECRET=$APPSECRET" >> "$CONFIG_FILE"
            echo "ACCESS_LEVEL=$ACCESS_LEVEL" >> "$CONFIG_FILE"
            echo "OAUTH_ACCESS_TOKEN=$OAUTH_ACCESS_TOKEN" >> "$CONFIG_FILE"
            echo "OAUTH_ACCESS_TOKEN_SECRET=$OAUTH_ACCESS_TOKEN_SECRET" >> "$CONFIG_FILE"

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

COMMAND=${@:$OPTIND:1}
ARG1=${@:$OPTIND+1:1}
ARG2=${@:$OPTIND+2:1}

#CHECKING PARAMS VALUES
case $COMMAND in

    upload)

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        #Checking FILE_SRC
        if [ ! -f "$FILE_SRC" -a ! -d "$FILE_SRC" ]; then
            echo -e "Error: No such file or directory: $FILE_SRC"
            remove_temp_files
            exit 1
        fi

        #Checking FILE_DST
        if [ -z "$FILE_DST" ]; then
            FILE_DST=/$(basename "$FILE_SRC")
        fi

        db_upload "$FILE_SRC" "$FILE_DST"

    ;;

    download)

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        #Checking FILE_SRC
        if [ -z "$FILE_SRC" ]; then
            echo -e "Error: Please specify the file to download"
            remove_temp_files
            exit 1
        fi

        db_download "$FILE_SRC" "$FILE_DST"

    ;;

    share)

        FILE_DST=$ARG1

        #Checking FILE_DST
        if [ -z "$FILE_DST" ]; then
            echo -e "Error: Please specify the file to share"
            remove_temp_files
            exit 1
        fi

        db_share "$FILE_DST"

    ;;

    info)

        db_account_info

    ;;

    delete|remove)

        FILE_DST=$ARG1

        #Checking FILE_DST
        if [ -z "$FILE_DST" ]; then
            echo -e "Error: Please specify the file to remove"
            remove_temp_files
            exit 1
        fi

        db_delete "$FILE_DST"

    ;;

    move|rename)

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        #Checking FILE_SRC
        if [ -z "$FILE_SRC" ]; then
            echo -e "Error: Please specify the source file"
            remove_temp_files
            exit 1
        fi

        #Checking FILE_DST
        if [ -z "$FILE_DST" ]; then
            echo -e "Error: Please specify the destination file"
            remove_temp_files
            exit 1
        fi

        db_move "$FILE_SRC" "$FILE_DST"

    ;;

    mkdir)

        DIR_DST=$ARG1

        #Checking DIR_DST
        if [ -z "$DIR_DST" ]; then
            echo -e "Error: Please specify the destination directory"
            remove_temp_files
            exit 1
        fi

        db_mkdir "$DIR_DST"

    ;;

    list)

        DIR_DST=$ARG1

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

        print "Error: Unknown command: $COMMAND\n\n"
        usage

    ;;

esac

remove_temp_files
exit 0
