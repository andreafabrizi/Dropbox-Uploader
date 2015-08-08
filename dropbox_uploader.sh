#!/usr/bin/env bash
#
# Dropbox Uploader
#
# Copyright (C) 2010-2014 Andrea Fabrizi <andrea.fabrizi@gmail.com>
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
SKIP_EXISTING_FILES=0
CHECK_MODIFIED=0
ERROR_STATUS=0
TIMEOUT_LONGPOLL=30 # Default value is 30 and it's the minimun allowed value - Max value is 480
PATHD="" # Default directory for Delta API

#Don't edit these...
API_REQUEST_TOKEN_URL="https://api.dropbox.com/1/oauth/request_token"
API_USER_AUTH_URL="https://www.dropbox.com/1/oauth/authorize"
API_ACCESS_TOKEN_URL="https://api.dropbox.com/1/oauth/access_token"
API_CHUNKED_UPLOAD_URL="https://api-content.dropbox.com/1/chunked_upload"
API_CHUNKED_UPLOAD_COMMIT_URL="https://api-content.dropbox.com/1/commit_chunked_upload"
API_UPLOAD_URL="https://api-content.dropbox.com/1/files_put"
API_DOWNLOAD_URL="https://api-content.dropbox.com/1/files"
API_DELETE_URL="https://api.dropbox.com/1/fileops/delete"
API_MOVE_URL="https://api.dropbox.com/1/fileops/move"
API_COPY_URL="https://api.dropbox.com/1/fileops/copy"
API_METADATA_URL="https://api.dropbox.com/1/metadata"
API_REVISIONS_URL="https://api.dropbox.com/1/revisions"
API_DELTA_URL="https://api.dropbox.com/1/delta"
API_DELTA_LATEST_CURSOR_URL="https://api.dropbox.com/1/delta/latest_cursor"
API_LONGPOLL_DELTA_URL="https://api-notify.dropbox.com/1/longpoll_delta"
API_INFO_URL="https://api.dropbox.com/1/account/info"
API_MKDIR_URL="https://api.dropbox.com/1/fileops/create_folder"
API_SHARES_URL="https://api.dropbox.com/1/shares"
API_SAVEURL_URL="https://api.dropbox.com/1/save_url/auto"
API_SAVEURL_JOB_URL="https://api.dropbox.com/1/save_url_job"
APP_CREATE_URL="https://www.dropbox.com/developers/apps"
RESPONSE_FILE="$TMP_DIR/du_resp_$RANDOM"
CHUNK_FILE="$TMP_DIR/du_chunk_$RANDOM"
TEMP_FILE="$TMP_DIR/du_tmp_$RANDOM"
BIN_DEPS="sed basename date grep stat dd mkdir"
VERSION="0.16"

umask 077

#Check the shell
if [ -z "$BASH_VERSION" ]; then
    echo -e "Error: this script requires the BASH shell!"
    exit 1
fi

shopt -s nullglob #Bash allows filename patterns which match no files to expand to a null string, rather than themselves
shopt -s dotglob  #Bash includes filenames beginning with a "." in the results of filename expansion

#Look for optional config file parameter
while getopts ":qpsmkdftx:" opt; do
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

    s)
      SKIP_EXISTING_FILES=1
    ;;

    m)
      CHECK_MODIFIED=1
    ;;

    t)
      if [[ $OPTARG -ge 30 && $OPTARG -le 480 ]]; then
        TIMEOUT_LONGPOLL=$OPTARG
      else
        echo "Option -$opt has a invalid argument: MIN value 30 and MAX value 480."
        exit 1
     fi
    ;;

    x)
     PATHD=$OPTARG
     if [ $(echo ${PATHD:0:1}) == "/" ]; then
       PATHD=$(echo ${PATHD:1})
     fi
     if [ $(echo ${PATHD: -1}) == "/" ]; then
      PATHD=$(echo ${PATHD:0:-1})
     fi
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

if [[ $DEBUG != 0 ]]; then
    echo $VERSION
    set -x
    RESPONSE_FILE="$TMP_DIR/du_resp_debug"
fi

if [[ $CURL_BIN == "" ]]; then
    BIN_DEPS="$BIN_DEPS curl"
    CURL_BIN="curl"
fi

#Dependencies check
which $BIN_DEPS > /dev/null
if [[ $? != 0 ]]; then
    for i in $BIN_DEPS; do
        which $i > /dev/null ||
            NOT_FOUND="$i $NOT_FOUND"
    done
    echo -e "Error: Required program could not be found: $NOT_FOUND"
    exit 1
fi

#Check if readlink is installed and supports the -m option
#It's not necessary, so no problem if it's not installed
which readlink > /dev/null
if [[ $? == 0 && $(readlink -m "//test" 2> /dev/null) == "/test" ]]; then
    HAVE_READLINK=1
else
    HAVE_READLINK=0
fi

#Forcing to use the builtin printf, if it's present, because it's better
#otherwise the external printf program will be used
#Note that the external printf command can cause character encoding issues!
builtin printf "" 2> /dev/null
if [[ $? == 0 ]]; then
    PRINTF="builtin printf"
    PRINTF_OPT="-v o"
else
    PRINTF=$(which printf)
    if [[ $? != 0 ]]; then
        echo -e "Error: Required program could not be found: printf"
    fi
    PRINTF_OPT=""
fi

#Print the message based on $QUIET variable
function print
{
    if [[ $QUIET == 0 ]]; then
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
    if [[ $DEBUG == 0 ]]; then
        rm -fr "$RESPONSE_FILE"
        rm -fr "$CHUNK_FILE"
        rm -fr "$TEMP_FILE"
    fi
}

#Returns the file size in bytes
function file_size
{
    #Generic GNU
    SIZE=$(stat --format="%s" "$1" 2> /dev/null)
    if [ $? -eq 0 ]; then
        echo $SIZE
        return
    fi

    #Some embedded linux devices
    SIZE=$(stat -c "%s" "$1" 2> /dev/null)
    if [ $? -eq 0 ]; then
        echo $SIZE
        return
    fi

    #BSD, OSX and other OSs
    SIZE=$(stat -f "%z" "$1" 2> /dev/null)
    if [ $? -eq 0 ]; then
        echo $SIZE
        return
    fi

    echo "0"
}

#Usage
function usage
{
    echo -e "Dropbox Uploader v$VERSION"
    echo -e "Andrea Fabrizi - andrea.fabrizi@gmail.com\n"
    echo -e "Usage: $0 COMMAND [PARAMETERS]..."
    echo -e "\nCommands:"

    echo -e "\t upload   <LOCAL_FILE/DIR ...>  <REMOTE_FILE/DIR>"
    echo -e "\t download <REMOTE_FILE/DIR> [LOCAL_FILE/DIR]"
    echo -e "\t delete   <REMOTE_FILE/DIR>"
    echo -e "\t move     <REMOTE_FILE/DIR> <REMOTE_FILE/DIR>"
    echo -e "\t copy     <REMOTE_FILE/DIR> <REMOTE_FILE/DIR>"
    echo -e "\t mkdir    <REMOTE_DIR>"
    echo -e "\t list     [REMOTE_DIR]"
    echo -e "\t share    <REMOTE_FILE>"
    echo -e "\t metadata <REMOTE_FILE/DIR>"
    echo -e "\t revisions <REMOTE_FILE/DIR>"
    echo -e "\t delta [CURSOR]"
    echo -e "\t latest_cursor"
    echo -e "\t longpoll_delta <CURSOR>"
    echo -e "\t saveurl  <URL> <REMOTE_DIR>"
    echo -e "\t info"
    echo -e "\t unlink"

    echo -e "\nOptional parameters:"
    echo -e "\t-f <FILENAME> Load the configuration file from a specific file"
    echo -e "\t-s            Skip already existing files when download/upload. Default: Overwrite"
    echo -e "\t-d            Enable DEBUG mode"
    echo -e "\t-q            Quiet mode. Don't show messages"
    echo -e "\t-p            Show cURL progress meter"
    echo -e "\t-k            Doesn't check for SSL certificates (insecure)"
    echo -e "\t-t [SECONDS]  Time that Longpoll Delta use for refresh: Default: 30 seconds. Max: 480"
    echo -e "\t-x <PATH>     Path for Delta or latest_cursor. Default: root (/)"

    echo -en "\nFor more info and examples, please see the README file.\n\n"
    remove_temp_files
    exit 1
}

#Check the curl exit code
function check_http_response
{
    CODE=$?

    #Checking curl exit code
    case $CODE in

        #OK
        0)

        ;;

        #Proxy error
        5)
            print "\nError: Couldn't resolve proxy. The given proxy host could not be resolved.\n"

            remove_temp_files
            exit 1
        ;;

        #Missing CA certificates
        60|58)
            print "\nError: cURL is not able to performs peer SSL certificate verification.\n"
            print "Please, install the default ca-certificates bundle.\n"
            print "To do this in a Debian/Ubuntu based system, try:\n"
            print "  sudo apt-get install ca-certificates\n\n"
            print "If the problem persists, try to use the -k option (insecure).\n"

            remove_temp_files
            exit 1
        ;;

        6)
            print "\nError: Couldn't resolve host.\n"

            remove_temp_files
            exit 1
        ;;

        7)
            print "\nError: Couldn't connect to host.\n"

            remove_temp_files
            exit 1
        ;;

    esac

    #Checking response file for generic errors
    if grep -q "HTTP/1.1 400" "$RESPONSE_FILE"; then
        ERROR_MSG=$(sed -n -e 's/{"error": "\([^"]*\)"}/\1/p' "$RESPONSE_FILE")

        case $ERROR_MSG in
             *access?attempt?failed?because?this?app?is?not?configured?to?have*)
                echo -e "\nError: The Permission type/Access level configured doesn't match the DropBox App settings!\nPlease run \"$0 unlink\" and try again."
                exit 1
            ;;
        esac

    fi
}

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
            * ) $PRINTF $PRINTF_OPT '%%%02x' "'$c"
        esac
        encoded="${encoded}${o}"
    done

    echo "$encoded"
}

function normalize_path
{
    path=$(echo -e "${1//\/\///}")
    if [[ $HAVE_READLINK == 1 ]]; then
        new_path=$(readlink -m "$path")

        #Adding back the final slash, if present in the source
        if [[ ${path: -1} == "/" && ${#path} > 1 ]]; then
            new_path="$new_path/"
        fi

        echo "$new_path"
    else
        echo "$path"
    fi
}

function db_metadata
{
    local FILE=$(normalize_path "$1")

    print " > Getting metadata for \"$FILE\"... $LINE_CR\n" >&2
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_METADATA_URL/$ACCESS_LEVEL/$(urlencode "$FILE")?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM&include_deleted=true" 2> /dev/null
    check_http_response
    JSON=$(sed -e '1,/^\r\{0,1\}$/d' -e 's/{"/{\n\"/g' -e 's/\",/\",\n/g' -e 's/\,\ \"/,\n\"/g' -e 's/\ \"/"/g' -e 's/\:\"/\:\ \"/g' -e 's/}/\n}/g' $RESPONSE_FILE)
    print "$JSON\n"
}

function db_revisions
{
    local FILE=$(normalize_path "$1")

    print " > Getting revisions for \"$FILE\"... $LINE_CR\n" >&2
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_REVISIONS_URL/$ACCESS_LEVEL/$(urlencode "$FILE")?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" 2> /dev/null
    check_http_response

    JSON=$(sed -e '1,/^\r\{0,1\}$/d' -e 's/\[/\[\n/g' -e 's/\]/\n\]/g' -e 's/{"/{\n\"/g' -e 's/\",/\",\n/g' -e 's/\,\ \"/,\n\"/g' -e 's/\ \"/"/g' -e 's/\:\"/\:\ \"/g' -e 's/}/\n}/g' -e 's/}, {/},\n{/g' $RESPONSE_FILE)
    print "$JSON\n"
}

function db_delta
{
    local CURSOR="$1"

    print " > Getting delta info...\n"
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" "$API_DELTA_URL?cursor=$CURSOR&path_prefix=/$PATHD" 2> /dev/null
    check_http_response

    JSON=$(sed -e '1,/^\r\{0,1\}$/d' -e 's/\[/\[\n/g' -e 's/\]/\n\]/g' -e 's/{"/{\n\"/g' -e 's/\",/\",\n/g' -e 's/\,\ \"/,\n\"/g' -e 's/\ \"/"/g' -e 's/\:\"/\:\ \"/g' -e 's/}/\n}/g' -e 's/}, {/},\n{/g' $RESPONSE_FILE)
    print "$JSON\n"
}

function db_delta_latest_cursor
{
    print " > Getting latest cursor...\n"
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" "$API_DELTA_LATEST_CURSOR_URL?path_prefix=/$PATHD" 2> /dev/null
    check_http_response

    JSON=$(sed -e '1,/^\r\{0,1\}$/d' -e 's/\[/\[\n/g' -e 's/\]/\n\]/g' -e 's/{"/{\n\"/g' -e 's/\",/\",\n/g' -e 's/\,\ \"/,\n\"/g' -e 's/\ \"/"/g' -e 's/\:\"/\:\ \"/g' -e 's/}/\n}/g' -e 's/}, {/},\n{/g' $RESPONSE_FILE)
    print "$JSON\n"
}

function db_longpoll_delta
{
    local CURSOR="$1"

    print " > Getting longpoll delta...\n"
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_LONGPOLL_DELTA_URL?cursor=$CURSOR&timeout=$TIMEOUT_LONGPOLL&oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET" 2> /dev/null
    check_http_response
# AQUI
    JSON=$(sed -e '1,/^\r\{0,1\}$/d' -e 's/\[/\[\n/g' -e 's/\]/\n\]/g' -e 's/{"/{\n\"/g' -e 's/\",/\",\n/g' -e 's/\,\ \"/,\n\"/g' -e 's/\ \"/"/g' -e 's/\:\"/\:\ \"/g' -e 's/}/\n}/g' -e 's/}, {/},\n{/g' $RESPONSE_FILE)
    print "$JSON\n"
}

#Check if it's a file or directory
#Returns FILE/DIR/ERR
function db_stat
{
    local FILE=$(normalize_path "$1")

    #Checking if it's a file or a directory
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_METADATA_URL/$ACCESS_LEVEL/$(urlencode "$FILE")?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" 2> /dev/null
    check_http_response

    #Even if the file/dir has been deleted from DropBox we receive a 200 OK response
    #So we must check if the file exists or if it has been deleted
    if grep -q "\"is_deleted\":" "$RESPONSE_FILE"; then
        local IS_DELETED=$(sed -n 's/.*"is_deleted":.\([^,]*\).*/\1/p' "$RESPONSE_FILE")
    else
        local IS_DELETED="false"
    fi

    #Exits...
    grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"
    if [[ $? == 0 && $IS_DELETED != "true" ]]; then

        local IS_DIR=$(sed -n 's/^\(.*\)\"contents":.\[.*/\1/p' "$RESPONSE_FILE")

        #It's a directory
        if [[ $IS_DIR != "" ]]; then
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
    local SRC=$(normalize_path "$1")
    local DST=$(normalize_path "$2")

    #Checking if the file/dir exists
    if [[ ! -e $SRC && ! -d $SRC ]]; then
        print " > No such file or directory: $SRC\n"
        ERROR_STATUS=1
        return
    fi

    #Checking if the file/dir has read permissions
    if [[ ! -r $SRC ]]; then
        print " > Error reading file $SRC: permission denied\n"
        ERROR_STATUS=1
        return
    fi

    TYPE=$(db_stat "$DST")

    #If DST it's a file, do nothing, it's the default behaviour
    if [[ $TYPE == "FILE" ]]; then
        DST="$DST"

    #if DST doesn't exists and doesn't ends with a /, it will be the destination file name
    elif [[ $TYPE == "ERR" && "${DST: -1}" != "/" ]]; then
        DST="$DST"

    #if DST doesn't exists and ends with a /, it will be the destination folder
    elif [[ $TYPE == "ERR" && "${DST: -1}" == "/" ]]; then
        local filename=$(basename "$SRC")
        DST="$DST/$filename"

    #If DST it'a directory, it will be the destination folder
    elif [[ $TYPE == "DIR" ]]; then
        local filename=$(basename "$SRC")
        DST="$DST/$filename"
    fi

    #It's a directory
    if [[ -d $SRC ]]; then
        db_upload_dir "$SRC" "$DST"

    #It's a file
    elif [[ -e $SRC ]]; then
        db_upload_file "$SRC" "$DST"

    #Unsupported object...
    else
        print " > Skipping not regular file \"$SRC\"\n"
    fi
}

#Generic upload wrapper around db_chunked_upload_file and db_simple_upload_file
#The final upload function will be choosen based on the file size
#$1 = Local source file
#$2 = Remote destination file
function db_upload_file
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    shopt -s nocasematch

    #Checking not allowed file names
    basefile_dst=$(basename "$FILE_DST")
    if [[ $basefile_dst == "thumbs.db" || \
          $basefile_dst == "desktop.ini" || \
          $basefile_dst == ".ds_store" || \
          $basefile_dst == "icon\r" || \
          $basefile_dst == ".dropbox" || \
          $basefile_dst == ".dropbox.attr" \
       ]]; then
        print " > Skipping not allowed file name \"$FILE_DST\"\n"
        return
    fi

    shopt -u nocasematch

    #Checking file size
    FILE_SIZE=$(file_size "$FILE_SRC")

    #Checking if the file already exists
    TYPE=$(db_stat "$FILE_DST")
    if [[ $TYPE != "ERR" && $SKIP_EXISTING_FILES == 1 ]]; then
        print " > Skipping already existing file \"$FILE_DST\"\n"
        return
    fi

    if [[ $FILE_SIZE -gt 157286000 ]]; then
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
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    if [[ $SHOW_PROGRESSBAR == 1 && $QUIET == 0 ]]; then
        CURL_PARAMETERS="--progress-bar"
        LINE_CR="\n"
    else
        CURL_PARAMETERS="-s"
        LINE_CR=""
    fi

    print " > Uploading \"$FILE_SRC\" to \"$FILE_DST\"... $LINE_CR"
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES $CURL_PARAMETERS -i --globoff -o "$RESPONSE_FILE" --upload-file "$FILE_SRC" "$API_UPLOAD_URL/$ACCESS_LEVEL/$(urlencode "$FILE_DST")?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM"
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        print "An error occurred requesting /upload\n"
        ERROR_STATUS=1
    fi
}

#Chunked file upload
#$1 = Local source file
#$2 = Remote destination file
function db_chunked_upload_file
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    print " > Uploading \"$FILE_SRC\" to \"$FILE_DST\""

    local FILE_SIZE=$(file_size "$FILE_SRC")
    local OFFSET=0
    local UPLOAD_ID=""
    local UPLOAD_ERROR=0
    local CHUNK_PARAMS=""

    #Uploading chunks...
    while ([[ $OFFSET != $FILE_SIZE ]]); do

        let OFFSET_MB=$OFFSET/1024/1024

        #Create the chunk
        dd if="$FILE_SRC" of="$CHUNK_FILE" bs=1048576 skip=$OFFSET_MB count=$CHUNK_SIZE 2> /dev/null

        #Only for the first request these parameters are not included
        if [[ $OFFSET != 0 ]]; then
            CHUNK_PARAMS="upload_id=$UPLOAD_ID&offset=$OFFSET"
        fi

        #Uploading the chunk...
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --upload-file "$CHUNK_FILE" "$API_CHUNKED_UPLOAD_URL?$CHUNK_PARAMS&oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" 2> /dev/null
        check_http_response

        #Check
        if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
            print "."
            UPLOAD_ERROR=0
            UPLOAD_ID=$(sed -n 's/.*"upload_id": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
            OFFSET=$(sed -n 's/.*"offset": *\([^}]*\).*/\1/p' "$RESPONSE_FILE")
        else
            print "*"
            let UPLOAD_ERROR=$UPLOAD_ERROR+1

            #On error, the upload is retried for max 3 times
            if [[ $UPLOAD_ERROR -gt 2 ]]; then
                print " FAILED\n"
                print "An error occurred requesting /chunked_upload\n"
                ERROR_STATUS=1
                return
            fi
        fi

    done

    UPLOAD_ERROR=0

    #Commit the upload
    while (true); do

        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "upload_id=$UPLOAD_ID&oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" "$API_CHUNKED_UPLOAD_COMMIT_URL/$ACCESS_LEVEL/$(urlencode "$FILE_DST")" 2> /dev/null
        check_http_response

        #Check
        if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
            print "."
            UPLOAD_ERROR=0
            break
        else
            print "*"
            let UPLOAD_ERROR=$UPLOAD_ERROR+1

            #On error, the commit is retried for max 3 times
            if [[ $UPLOAD_ERROR -gt 2 ]]; then
                print " FAILED\n"
                print "An error occurred requesting /commit_chunked_upload\n"
                ERROR_STATUS=1
                return
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
    local DIR_SRC=$(normalize_path "$1")
    local DIR_DST=$(normalize_path "$2")

    #Creatig remote directory
    db_mkdir "$DIR_DST"

    for file in "$DIR_SRC/"*; do
        db_upload "$file" "$DIR_DST"
    done
}

#Generic download wrapper
#$1 = Remote source file/dir
#$2 = Local destination file/dir
function db_download
{
    local SRC=$(normalize_path "$1")
    local DST=$(normalize_path "$2")

    TYPE=$(db_stat "$SRC")

    #It's a directory
    if [[ $TYPE == "DIR" ]]; then

        #If the DST folder is not specified, I assume that is the current directory
        if [[ $DST == "" ]]; then
            DST="."
        fi

        #Checking if the destination directory exists
        if [[ ! -d $DST ]]; then
            local basedir=""
        else
            local basedir=$(basename "$SRC")
        fi

        local DEST_DIR=$(normalize_path "$DST/$basedir")
        print " > Downloading \"$SRC\" to \"$DEST_DIR\"... \n"
        print " > Creating local directory \"$DEST_DIR\"... "
        mkdir -p "$DEST_DIR"

        #Check
        if [[ $? == 0 ]]; then
            print "DONE\n"
        else
            print "FAILED\n"
            ERROR_STATUS=1
            return
        fi

        #Extracting directory content [...]
        #and replacing "}, {" with "}\n{"
        #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
        local DIR_CONTENT=$(sed -n 's/.*: \[{\(.*\)/\1/p' "$RESPONSE_FILE" | sed 's/}, *{/}\
{/g')

        #Extracting files and subfolders
        TMP_DIR_CONTENT_FILE="${RESPONSE_FILE}_$RANDOM"
        echo "$DIR_CONTENT" | sed -n 's/.*"path": *"\([^"]*\)",.*"is_dir": *\([^"]*\),.*/\1:\2/p' > $TMP_DIR_CONTENT_FILE

        #For each entry...
        while read -r line; do

            local FILE=${line%:*}
            local TYPE=${line#*:}

            #Removing unneeded /
            FILE=${FILE##*/}

            if [[ $TYPE == "false" ]]; then
                db_download_file "$SRC/$FILE" "$DEST_DIR/$FILE"
            else
                db_download "$SRC/$FILE" "$DEST_DIR"
            fi

        done < $TMP_DIR_CONTENT_FILE

        rm -fr $TMP_DIR_CONTENT_FILE

    #It's a file
    elif [[ $TYPE == "FILE" ]]; then

        #Checking DST
        if [[ $DST == "" ]]; then
            DST=$(basename "$SRC")
        fi

        #If the destination is a directory, the file will be download into
        if [[ -d $DST ]]; then
            DST="$DST/$SRC"
        fi

        db_download_file "$SRC" "$DST"

    #Doesn't exists
    else
        print " > No such file or directory: $SRC\n"
        ERROR_STATUS=1
        return
    fi
}

#Simple file download
#$1 = Remote source file
#$2 = Local destination file
function db_download_file
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    if [[ $SHOW_PROGRESSBAR == 1 && $QUIET == 0 ]]; then
        CURL_PARAMETERS="--progress-bar"
        LINE_CR="\n"
    else
        CURL_PARAMETERS="-s"
        LINE_CR=""
    fi

    #Checking if the file already exists
    if [[ -e $FILE_DST && $SKIP_EXISTING_FILES == 1 ]]; then
        print " > Skipping already existing file \"$FILE_DST\"\n"
        return
    fi

    #Don't download files with modified timestamps equal or higher than upstream if -m is present.
    if [[ -e $FILE_DST && $CHECK_MODIFIED == 1 ]]; then
      #Checking if the file has changed
      LOCAL_LAST_MODIFIED=$(stat --printf="%Y" ".$FILE_SRC")
      $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_METADATA_URL/$ACCESS_LEVEL/$(urlencode "$FILE_DST")?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" 2> /dev/null
      DATE=$(sed '1,/^\r\{0,1\}$/d' $RESPONSE_FILE | grep -Po '"modified":.*?[^\\]",' | sed 's/"modified":\s*//g' | sed 's/[",]//g')
      REMOTE_LAST_MODIFIED=$(date --date="$DATE" +%s)
      if [ "$REMOTE_LAST_MODIFIED" -gt "$LOCAL_LAST_MODIFIED" ]; then
        echo "File '"$FILE_SRC"' has changed on Dropbox, downlading..." >&2
      else
        echo "File '"$FILE_SRC"' up to date, skipping as requested by -m flag."
        return
      fi
    fi

    #Creating the empty file, that for two reasons:
    #1) In this way I can check if the destination file is writable or not
    #2) Curl doesn't automatically creates files with 0 bytes size
    dd if=/dev/zero of="$FILE_DST" count=0 2> /dev/null
    if [[ $? != 0 ]]; then
        print " > Error writing file $FILE_DST: permission denied\n"
        ERROR_STATUS=1
        return
    fi

    print " > Downloading \"$FILE_SRC\" to \"$FILE_DST\"... $LINE_CR"
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES $CURL_PARAMETERS --globoff -D "$RESPONSE_FILE" -o "$FILE_DST" "$API_DOWNLOAD_URL/$ACCESS_LEVEL/$(urlencode "$FILE_SRC")?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM"
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        rm -fr "$FILE_DST"
        ERROR_STATUS=1
        return
    fi
}

#Saveurl
#$1 = URL
#$2 = Remote file destination
function db_saveurl
{
    local URL="$1"
    local FILE_DST=$(normalize_path "$2")
    local FILE_NAME=$(basename "$URL")

    print " > Downloading \"$URL\" to \"$FILE_DST\"..."
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "url=$(urlencode "$URL")&oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" "$API_SAVEURL_URL/$FILE_DST/$FILE_NAME" 2> /dev/null
    check_http_response

    JOB_ID=$(sed -n 's/.*"job": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
    if [[ $JOB_ID == "" ]]; then
        print " > Error getting the job id\n"
        return
    fi

    #Checking the status
    while (true); do

        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" "$API_SAVEURL_JOB_URL/$JOB_ID" 2> /dev/null
        check_http_response

        STATUS=$(sed -n 's/.*"status": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
        case $STATUS in

            PENDING)
                print "."
            ;;

            DOWNLOADING)
                print "+"
            ;;

            COMPLETE)
                print " DONE\n"
                break
            ;;

            FAILED)
                print " ERROR\n"
                MESSAGE=$(sed -n 's/.*"error": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
                print " > Error: $MESSAGE\n"
                break
            ;;

        esac

        sleep 2

    done
}

#Prints account info
function db_account_info
{
    print "Dropbox Uploader v$VERSION\n\n"
    print " > Getting info... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" "$API_INFO_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

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
        ERROR_STATUS=1
    fi
}

#Account unlink
function db_unlink
{
    echo -ne "Are you sure you want unlink this script from your Dropbox account? [y/n]"
    read answer
    if [[ $answer == "y" ]]; then
        rm -fr "$CONFIG_FILE"
        echo -ne "DONE\n"
    fi
}

#Delete a remote file
#$1 = Remote file to delete
function db_delete
{
    local FILE_DST=$(normalize_path "$1")

    print " > Deleting \"$FILE_DST\"... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM&root=$ACCESS_LEVEL&path=$(urlencode "$FILE_DST")" "$API_DELETE_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Move/Rename a remote file
#$1 = Remote file to rename or move
#$2 = New file name or location
function db_move
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    TYPE=$(db_stat "$FILE_DST")

    #If the destination it's a directory, the source will be moved into it
    if [[ $TYPE == "DIR" ]]; then
        local filename=$(basename "$FILE_SRC")
        FILE_DST=$(normalize_path "$FILE_DST/$filename")
    fi

    print " > Moving \"$FILE_SRC\" to \"$FILE_DST\" ... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM&root=$ACCESS_LEVEL&from_path=$(urlencode "$FILE_SRC")&to_path=$(urlencode "$FILE_DST")" "$API_MOVE_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Copy a remote file to a remote location
#$1 = Remote file to rename or move
#$2 = New file name or location
function db_copy
{
    local FILE_SRC=$(normalize_path "$1")
    local FILE_DST=$(normalize_path "$2")

    TYPE=$(db_stat "$FILE_DST")

    #If the destination it's a directory, the source will be copied into it
    if [[ $TYPE == "DIR" ]]; then
        local filename=$(basename "$FILE_SRC")
        FILE_DST=$(normalize_path "$FILE_DST/$filename")
    fi

    print " > Copying \"$FILE_SRC\" to \"$FILE_DST\" ... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM&root=$ACCESS_LEVEL&from_path=$(urlencode "$FILE_SRC")&to_path=$(urlencode "$FILE_DST")" "$API_COPY_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Create a new directory
#$1 = Remote directory to create
function db_mkdir
{
    local DIR_DST=$(normalize_path "$1")

    print " > Creating Directory \"$DIR_DST\"... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM&root=$ACCESS_LEVEL&path=$(urlencode "$DIR_DST")" "$API_MKDIR_URL" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print "DONE\n"
    elif grep -q "^HTTP/1.1 403 Forbidden" "$RESPONSE_FILE"; then
        print "ALREADY EXISTS\n"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#List remote directory
#$1 = Remote directory
function db_list
{
    local DIR_DST=$(normalize_path "$1")

    print " > Listing \"$DIR_DST\"... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_METADATA_URL/$ACCESS_LEVEL/$(urlencode "$DIR_DST")?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then

        local IS_DIR=$(sed -n 's/^\(.*\)\"contents":.\[.*/\1/p' "$RESPONSE_FILE")

        #It's a directory
        if [[ $IS_DIR != "" ]]; then

            print "DONE\n"

            #Extracting directory content [...]
            #and replacing "}, {" with "}\n{"
            #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
            local DIR_CONTENT=$(sed -n 's/.*: \[{\(.*\)/\1/p' "$RESPONSE_FILE" | sed 's/}, *{/}\
{/g')

            #Converting escaped quotes to unicode format
            echo "$DIR_CONTENT" | sed 's/\\"/\\u0022/' > "$TEMP_FILE"

            #Extracting files and subfolders
            rm -fr "$RESPONSE_FILE"
            while read -r line; do

                local FILE=$(echo "$line" | sed -n 's/.*"path": *"\([^"]*\)".*/\1/p')
                local IS_DIR=$(echo "$line" | sed -n 's/.*"is_dir": *\([^,]*\).*/\1/p')
                local SIZE=$(echo "$line" | sed -n 's/.*"bytes": *\([0-9]*\).*/\1/p')

                echo -e "$FILE:$IS_DIR;$SIZE" >> "$RESPONSE_FILE"

            done < "$TEMP_FILE"

            #Looking for the biggest file size
            #to calculate the padding to use
            local padding=0
            while read -r line; do
                local FILE=${line%:*}
                local META=${line##*:}
                local SIZE=${META#*;}

                if [[ ${#SIZE} -gt $padding ]]; then
                    padding=${#SIZE}
                fi
            done < "$RESPONSE_FILE"

            #For each entry, printing directories...
            while read -r line; do

                local FILE=${line%:*}
                local META=${line##*:}
                local TYPE=${META%;*}
                local SIZE=${META#*;}

                #Removing unneeded /
                FILE=${FILE##*/}

                if [[ $TYPE == "true" ]]; then
                    FILE=$(echo -e "$FILE")
                    $PRINTF " [D] %-${padding}s %s\n" "$SIZE" "$FILE"
                fi

            done < "$RESPONSE_FILE"

            #For each entry, printing files...
            while read -r line; do

                local FILE=${line%:*}
                local META=${line##*:}
                local TYPE=${META%;*}
                local SIZE=${META#*;}

                #Removing unneeded /
                FILE=${FILE##*/}

                if [[ $TYPE == "false" ]]; then
                    FILE=$(echo -e "$FILE")
                    $PRINTF " [F] %-${padding}s %s\n" "$SIZE" "$FILE"
                fi

            done < "$RESPONSE_FILE"

        #It's a file
        else
            print "FAILED: $DIR_DST is not a directory!\n"
            ERROR_STATUS=1
        fi

    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

#Share remote file
#$1 = Remote file
function db_share
{
    local FILE_DST=$(normalize_path "$1")

    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" "$API_SHARES_URL/$ACCESS_LEVEL/$(urlencode "$FILE_DST")?oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_ACCESS_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_ACCESS_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM&short_url=true" 2> /dev/null
    check_http_response

    #Check
    if grep -q "^HTTP/1.1 200 OK" "$RESPONSE_FILE"; then
        print " > Share link: "
        SHARE_LINK=$(sed -n 's/.*"url": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
        echo "$SHARE_LINK"
    else
        print "FAILED\n"
        ERROR_STATUS=1
    fi
}

################
#### SETUP  ####
################

#CHECKING FOR AUTH FILE
if [[ -e $CONFIG_FILE ]]; then

    #Loading data... and change old format config if necesary.
    source "$CONFIG_FILE" 2>/dev/null || {
        sed -i'' 's/:/=/' "$CONFIG_FILE" && source "$CONFIG_FILE" 2>/dev/null
    }

    #Checking the loaded data
    if [[ $APPKEY == "" || $APPSECRET == "" || $OAUTH_ACCESS_TOKEN_SECRET == "" || $OAUTH_ACCESS_TOKEN == "" ]]; then
        echo -ne "Error loading data from $CONFIG_FILE...\n"
        echo -ne "It is recommended to run $0 unlink\n"
        remove_temp_files
        exit 1
    fi

    #Back compatibility with previous Dropbox Uploader versions
    if [[ $ACCESS_LEVEL == "" ]]; then
        ACCESS_LEVEL="dropbox"
    fi

#NEW SETUP...
else

    echo -ne "\n This is the first time you run this script.\n\n"
    echo -ne " 1) Open the following URL in your Browser, and log in using your account: $APP_CREATE_URL\n"
    echo -ne " 2) Click on \"Create App\", then select \"Dropbox API app\"\n"
    echo -ne " 3) Now go on with the configuration, choosing the app permissions and access restrictions to your DropBox folder\n"
    echo -ne " 4) Enter the \"App Name\" that you prefer (e.g. MyUploader$RANDOM$RANDOM$RANDOM)\n\n"

    echo -ne " Now, click on the \"Create App\" button.\n\n"

    echo -ne " When your new App is successfully created, please type the\n"
    echo -ne " App Key, App Secret and the Permission type shown in the confirmation page:\n\n"

    #Getting the app key and secret from the user
    while (true); do

        echo -ne " # App key: "
        read APPKEY

        echo -ne " # App secret: "
        read APPSECRET

        echo -ne "\nPermission type:\n App folder [a]: If you choose that the app only needs access to files it creates\n Full Dropbox [f]: If you choose that the app needs access to files already on Dropbox\n\n # Permission type [a/f]: "
        read ACCESS_LEVEL

        if [[ $ACCESS_LEVEL == "a" ]]; then
            ACCESS_LEVEL="sandbox"
            ACCESS_MSG="App Folder"
        else
            ACCESS_LEVEL="dropbox"
            ACCESS_MSG="Full Dropbox"
        fi

        echo -ne "\n > App key is $APPKEY, App secret is $APPSECRET and Access level is $ACCESS_MSG. Looks ok? [y/n]: "
        read answer
        if [[ $answer == "y" ]]; then
            break;
        fi

    done

    #TOKEN REQUESTS
    echo -ne "\n > Token request... "
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" "$API_REQUEST_TOKEN_URL" 2> /dev/null
    check_http_response
    OAUTH_TOKEN_SECRET=$(sed -n 's/oauth_token_secret=\([a-z A-Z 0-9]*\).*/\1/p' "$RESPONSE_FILE")
    OAUTH_TOKEN=$(sed -n 's/.*oauth_token=\([a-z A-Z 0-9]*\)/\1/p' "$RESPONSE_FILE")

    if [[ $OAUTH_TOKEN != "" && $OAUTH_TOKEN_SECRET != "" ]]; then
        echo -ne "OK\n"
    else
        echo -ne " FAILED\n\n Please, check your App key and secret...\n\n"
        remove_temp_files
        exit 1
    fi

    while (true); do

        #USER AUTH
        echo -ne "\n Please open the following URL in your browser, and allow Dropbox Uploader\n"
        echo -ne " to access your DropBox folder:\n\n --> ${API_USER_AUTH_URL}?oauth_token=$OAUTH_TOKEN\n"
        echo -ne "\nPress enter when done...\n"
        read

        #API_ACCESS_TOKEN_URL
        echo -ne " > Access Token request... "
        $CURL_BIN $CURL_ACCEPT_CERTIFICATES -s --show-error --globoff -i -o "$RESPONSE_FILE" --data "oauth_consumer_key=$APPKEY&oauth_token=$OAUTH_TOKEN&oauth_signature_method=PLAINTEXT&oauth_signature=$APPSECRET%26$OAUTH_TOKEN_SECRET&oauth_timestamp=$(utime)&oauth_nonce=$RANDOM" "$API_ACCESS_TOKEN_URL" 2> /dev/null
        check_http_response
        OAUTH_ACCESS_TOKEN_SECRET=$(sed -n 's/oauth_token_secret=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_TOKEN=$(sed -n 's/.*oauth_token=\([a-z A-Z 0-9]*\)&.*/\1/p' "$RESPONSE_FILE")
        OAUTH_ACCESS_UID=$(sed -n 's/.*uid=\([0-9]*\)/\1/p' "$RESPONSE_FILE")

        if [[ $OAUTH_ACCESS_TOKEN != "" && $OAUTH_ACCESS_TOKEN_SECRET != "" && $OAUTH_ACCESS_UID != "" ]]; then
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
            ERROR_STATUS=1
        fi

    done;

    remove_temp_files
    exit $ERROR_STATUS
fi

################
#### START  ####
################

COMMAND=${@:$OPTIND:1}
ARG1=${@:$OPTIND+1:1}
ARG2=${@:$OPTIND+2:1}

let argnum=$#-$OPTIND

#CHECKING PARAMS VALUES
case $COMMAND in

    upload)

        if [[ $argnum -lt 2 ]]; then
            usage
        fi

        FILE_DST=${@:$#:1}

        for (( i=$OPTIND+1; i<$#; i++ )); do
            FILE_SRC=${@:$i:1}
            db_upload "$FILE_SRC" "/$FILE_DST"
        done

    ;;

    download)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        db_download "/$FILE_SRC" "$FILE_DST"

    ;;

    saveurl)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        URL=$ARG1
        FILE_DST=$ARG2

        db_saveurl "$URL" "/$FILE_DST"

    ;;

    share)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        FILE_DST=$ARG1

        db_share "/$FILE_DST"

    ;;

    metadata)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        FILE_DST=$ARG1

        db_metadata "/$FILE_DST"

    ;;

    revisions)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        FILE_DST=$ARG1

        db_revisions "/$FILE_DST"

    ;;

    delta)

        if [[ $argnum -lt 1 ]]; then
            db_delta
        else
            CURSOR=$ARG1
            db_delta "$CURSOR"
    	fi

    ;;

    latest_cursor)

        db_delta_latest_cursor

    ;;

    longpoll_delta)
        if [[ $argnum -lt 1 ]]; then
            usage
        fi
        CURSOR=$ARG1
        db_longpoll_delta "$CURSOR"

    ;;

    info)

        db_account_info


    ;;

    delete|remove)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        FILE_DST=$ARG1

        db_delete "/$FILE_DST"

    ;;

    move|rename)

        if [[ $argnum -lt 2 ]]; then
            usage
        fi

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        db_move "/$FILE_SRC" "/$FILE_DST"

    ;;

    copy)

        if [[ $argnum -lt 2 ]]; then
            usage
        fi

        FILE_SRC=$ARG1
        FILE_DST=$ARG2

        db_copy "/$FILE_SRC" "/$FILE_DST"

    ;;

    mkdir)

        if [[ $argnum -lt 1 ]]; then
            usage
        fi

        DIR_DST=$ARG1

        db_mkdir "/$DIR_DST"

    ;;

    list)

        DIR_DST=$ARG1

        #Checking DIR_DST
        if [[ $DIR_DST == "" ]]; then
            DIR_DST="/"
        fi

        db_list "/$DIR_DST"

    ;;

    unlink)

        db_unlink

    ;;

    *)

        if [[ $COMMAND != "" ]]; then
            print "Error: Unknown command: $COMMAND\n\n"
            ERROR_STATUS=1
        fi
        usage

    ;;

esac

remove_temp_files
exit $ERROR_STATUS
