#!/usr/bin/env bash
#
# Dropbox Uploader
#
# Copyright (C) 2010-2021 Andrea Fabrizi <andrea.fabrizi@gmail.com>
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
CHUNK_SIZE=50

#Curl location
#If not set, curl will be searched into the $PATH
#CURL_BIN="/usr/bin/curl"

#Default values
TMP_DIR="/tmp"
DEBUG=0
QUIET=0
SHOW_PROGRESSBAR=0
SKIP_EXISTING_FILES=0
ERROR_STATUS=0
EXCLUDE=()

#Don't edit these...
API_OAUTH_TOKEN="https://api.dropbox.com/oauth2/token"
API_OAUTH_AUTHORIZE="https://www.dropbox.com/oauth2/authorize"
API_LONGPOLL_FOLDER="https://notify.dropboxapi.com/2/files/list_folder/longpoll"
API_CHUNKED_UPLOAD_START_URL="https://content.dropboxapi.com/2/files/upload_session/start"
API_CHUNKED_UPLOAD_FINISH_URL="https://content.dropboxapi.com/2/files/upload_session/finish"
API_CHUNKED_UPLOAD_APPEND_URL="https://content.dropboxapi.com/2/files/upload_session/append_v2"
API_UPLOAD_URL="https://content.dropboxapi.com/2/files/upload"
API_DOWNLOAD_URL="https://content.dropboxapi.com/2/files/download"
API_DELETE_URL="https://api.dropboxapi.com/2/files/delete"
API_MOVE_URL="https://api.dropboxapi.com/2/files/move"
API_COPY_URL="https://api.dropboxapi.com/2/files/copy"
API_METADATA_URL="https://api.dropboxapi.com/2/files/get_metadata"
API_LIST_FOLDER_URL="https://api.dropboxapi.com/2/files/list_folder"
API_LIST_FOLDER_CONTINUE_URL="https://api.dropboxapi.com/2/files/list_folder/continue"
API_ACCOUNT_INFO_URL="https://api.dropboxapi.com/2/users/get_current_account"
API_ACCOUNT_SPACE_URL="https://api.dropboxapi.com/2/users/get_space_usage"
API_MKDIR_URL="https://api.dropboxapi.com/2/files/create_folder"
API_SHARE_URL="https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings"
API_SHARE_LIST="https://api.dropboxapi.com/2/sharing/list_shared_links"
API_SAVEURL_URL="https://api.dropboxapi.com/2/files/save_url"
API_SAVEURL_JOBSTATUS_URL="https://api.dropboxapi.com/2/files/save_url/check_job_status"
API_SEARCH_URL="https://api.dropboxapi.com/2/files/search"
APP_CREATE_URL="https://www.dropbox.com/developers/apps"
RESPONSE_FILE="$TMP_DIR/du_resp_$RANDOM"
CHUNK_FILE="$TMP_DIR/du_chunk_$RANDOM"
TEMP_FILE="$TMP_DIR/du_tmp_$RANDOM"
OAUTH_ACCESS_TOKEN_EXPIRE="0"
OAUTH_ACCESS_TOKEN=""
BIN_DEPS="sed basename date grep stat dd mkdir"
VERSION="1.0"

umask 077

#Check the shell
if [ -z "$BASH_VERSION" ]; then
  echo -e "Error: this script requires the BASH shell!"
  exit 1
fi

shopt -s nullglob #Bash allows filename patterns which match no files to expand to a null string, rather than themselves
shopt -s dotglob  #Bash includes filenames beginning with a "." in the results of filename expansion

#Check temp folder
if [[ ! -d "${TMP_DIR}" ]]; then
  echo -e "Error: the temporary folder ${TMP_DIR} doesn't exists!"
  echo -e "Please edit this script and set the TMP_DIR variable to a valid temporary folder to use."
  exit 1
fi

#Look for optional config file parameter
while getopts ":qpskdhf:x:" opt; do
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

  h)
    HUMAN_READABLE_SIZE=1
    ;;

  x)
    EXCLUDE+=("$OPTARG")
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

if [[ $DEBUG -ne 0 ]]; then
  echo $VERSION
  uname -a 2>/dev/null
  cat /etc/issue 2>/dev/null
  set -x
  RESPONSE_FILE="$TMP_DIR/du_resp_debug"
fi

if [[ $CURL_BIN == "" ]]; then
  BIN_DEPS="$BIN_DEPS curl"
  CURL_BIN="curl"
fi

#Dependencies check
which $BIN_DEPS >/dev/null
if [[ $? -ne 0 ]]; then
  for BIN_DEP in $BIN_DEPS; do
    which "${BIN_DEP}" >/dev/null ||
      NOT_FOUND="${BIN_DEP} $NOT_FOUND"
  done
  echo -e "Error: Required program could not be found: $NOT_FOUND"
  exit 1
fi

#Check if readlink is installed and supports the -m option
#It's not necessary, so no problem if it's not installed
which readlink >/dev/null
if [[ $? -eq 0 && $(readlink -m "//test" 2>/dev/null) == "/test" ]]; then
  HAVE_READLINK=1
else
  HAVE_READLINK=0
fi

#Forcing to use the builtin printf, if it's present, because it's better
#otherwise the external printf program will be used
#Note that the external printf command can cause character encoding issues!
builtin printf "" 2>/dev/null
if [[ $? -eq 0 ]]; then
  PRINTF="builtin printf"
  PRINTF_OPT="-v o"
else
  PRINTF=$(which printf)
  if [[ $? -ne 0 ]]; then
    echo -e "Error: Required program could not be found: printf"
  fi
  PRINTF_OPT=""
fi

#Print the message based on $QUIET variable
function print() {
  if [[ $QUIET -eq 0 ]]; then
    echo -ne "$1"
  fi
}

#Returns unix timestamp
function utime() {
  date '+%s'
}

#Remove temporary files
function remove_temp_files() {
  if [[ $DEBUG == 0 ]]; then
    rm -fr "$RESPONSE_FILE"
    rm -fr "$CHUNK_FILE"
    rm -fr "$TEMP_FILE"
  fi
}

#Converts bytes to human readable format
function convert_bytes() {
  if [[ $HUMAN_READABLE_SIZE == 1 && "$1" != "" ]]; then
    if (($1 > 1073741824)); then
      echo $(($1 / 1073741824)).$(($1 % 1073741824 / 100000000))"G"
    elif (($1 > 1048576)); then
      echo $(($1 / 1048576)).$(($1 % 1048576 / 100000))"M"
    elif (($1 > 1024)); then
      echo $(($1 / 1024)).$(($1 % 1024 / 100))"K"
    else
      echo "$1"
    fi
  else
    echo "$1"
  fi
}

#Returns the file size in bytes
function file_size() {
  local size
  #Generic GNU
  size=$(stat --format="%s" "$1" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "$size"
    return
  fi

  #Some embedded linux devices
  size=$(stat -c "%s" "$1" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "$size"
    return
  fi

  #BSD, OSX and other OSs
  size=$(stat -f "%z" "$1" 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "$size"
    return
  fi

  echo "0"
}

#Usage
function usage() {
  echo -e "Dropbox Uploader v$VERSION"
  echo -e "Andrea Fabrizi - andrea.fabrizi@gmail.com\n"
  echo -e "Usage: $0 [PARAMETERS] COMMAND..."
  echo -e "\nCommands:"

  echo -e "\t upload   <LOCAL_FILE/DIR ...>  <REMOTE_FILE/DIR>"
  echo -e "\t download <REMOTE_FILE/DIR> [LOCAL_FILE/DIR]"
  echo -e "\t delete   <REMOTE_FILE/DIR>"
  echo -e "\t move     <REMOTE_FILE/DIR> <REMOTE_FILE/DIR>"
  echo -e "\t copy     <REMOTE_FILE/DIR> <REMOTE_FILE/DIR>"
  echo -e "\t mkdir    <REMOTE_DIR>"
  echo -e "\t list     [REMOTE_DIR]"
  echo -e "\t monitor  [REMOTE_DIR] [TIMEOUT]"
  echo -e "\t share    <REMOTE_FILE>"
  echo -e "\t saveurl  <URL> <REMOTE_DIR>"
  echo -e "\t search   <QUERY>"
  echo -e "\t info"
  echo -e "\t space"
  echo -e "\t unlink"

  echo -e "\nOptional parameters:"
  echo -e "\t-f <FILENAME> Load the configuration file from a specific file"
  echo -e "\t-s            Skip already existing files when download/upload. Default: Overwrite"
  echo -e "\t-d            Enable DEBUG mode"
  echo -e "\t-q            Quiet mode. Don't show messages"
  echo -e "\t-h            Show file sizes in human readable format"
  echo -e "\t-p            Show cURL progress meter"
  echo -e "\t-k            Doesn't check for SSL certificates (insecure)"
  echo -e "\t-x            Ignores/excludes directories or files from syncing. -x filename -x directoryname. example: -x .git"

  echo -en "\nFor more info and examples, please see the README file.\n\n"
  remove_temp_files
  exit 1
}

#Check the curl exit code
function check_http_response() {
  local code
  code=$1
  #Checking curl exit code

  case $code in
  #OK

  0) ;;

  #Proxy error
  5)
    print "\nError: Couldn't resolve proxy. The given proxy host could not be resolved.\n"

    remove_temp_files
    exit 1
    ;;

  #Missing CA certificates
  60 | 58 | 77)
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
  if grep -q "^HTTP/[12].* 400" "$RESPONSE_FILE"; then
    local error_msg
    error_msg=$(sed -n -e 's/{"error": "\([^"]*\)"}/\1/p' "$RESPONSE_FILE")

    case $error_msg in
    *access?attempt?failed?because?this?app?is?not?configured?to?have*)
      echo -e "\nError: The Permission type/Access level configured doesn't match the DropBox App settings!\nPlease run \"$0 unlink\" and try again."
      exit 1
      ;;
    esac

  fi

}

# Checks if the access token has expired. If so a new one is created.
function ensure_accesstoken() {
  local now expires_in

  now=$(date +%s)

  # This does not do anything
  if [[ $OAUTH_ACCESS_TOKEN_EXPIRE > $now ]]; then
    return
  fi

  $CURL_BIN $CURL_ACCEPT_CERTIFICATES $API_OAUTH_TOKEN -d grant_type=refresh_token -d refresh_token=$OAUTH_REFRESH_TOKEN -u $OAUTH_APP_KEY:$OAUTH_APP_SECRET -o "$RESPONSE_FILE" 2>/dev/null
  check_http_response $?

  OAUTH_ACCESS_TOKEN=$(sed -n 's/.*"access_token": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")

  expires_in=$(sed -n 's/.*"expires_in": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")

  # one minute safety buffer
  OAUTH_ACCESS_TOKEN_EXPIRE=$((now + expires_in - 60))
}

#Urlencode
function urlencode() {
  local string strlen encoded
  #The printf is necessary to correctly decode unicode sequences
  string=$($PRINTF "%s" "${1}")
  strlen=${#string}
  encoded=""

  for ((pos = 0; pos < strlen; pos++)); do
    local c
    c=${string:$pos:1}
    case "$c" in
    [-_.~a-zA-Z0-9]) o="${c}" ;;
    *) $PRINTF $PRINTF_OPT '%%%02x' "'$c" ;;
    esac
    encoded="${encoded}${o}"
  done

  echo "$encoded"
}

function normalize_path() {
  local path new_path
  #The printf is necessary to correctly decode unicode sequences
  path=$($PRINTF "%s" "${1//\/\///}")
  if [[ $HAVE_READLINK == 1 ]]; then
    new_path=$(readlink -m "$path")
    #Adding back the final slash, if present in the source
    if [[ ${path: -1} == "/" && ${#path} -gt 1 ]]; then
      new_path="$new_path/"
    fi
    echo "$new_path"
  else
    echo "$path"
  fi
}

#Check if it's a file or directory
#Returns FILE/DIR/ERR
function db_stat() {
  local file type
  file=$(normalize_path "$1")

  if [[ $file == "/" ]]; then
    echo "DIR"
    return
  fi

  #Checking if it's a file or a directory
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$file\"}" "$API_METADATA_URL" 2>/dev/null
  check_http_response $?

  type=$(sed -n 's/{".tag": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")

  case $type in

  file)
    echo "FILE"
    ;;

  folder)
    echo "DIR"
    ;;

  deleted)
    echo "ERR"
    ;;

  *)
    echo "ERR"
    ;;

  esac
}

#Generic upload wrapper around db_upload_file and db_upload_dir functions
#$1 = Local source file/dir
#$2 = Remote destination file/dir
function db_upload() {
  local src dst type
  src=$(normalize_path "$1")
  dst=$(normalize_path "$2")

  echo "SRC: ${src}"
  echo "DST: ${dst}"
  for j in "${EXCLUDE[@]}"; do
    echo "$src" | grep -c "$j"
    if [[ $(echo "$src" | grep -c "$j") -gt 0 ]]; then
      print "Skipping excluded file/dir: $j"
      return
    fi
  done

  #Checking if the file/dir exists
  if [[ ! -e $src && ! -d $src ]]; then
    print " > No such file or directory: $src\n"
    ERROR_STATUS=1
    return
  fi

  #Checking if the file/dir has read permissions
  if [[ ! -r $src ]]; then
    print " > Error reading file $src: permission denied\n"
    ERROR_STATUS=1
    return
  fi

  type=$(db_stat "$dst")

  #If dst it's a file, do nothing, it's the default behaviour
  if [[ $type == "FILE" ]]; then
    dst="$dst"

  #if dst doesn't exists and doesn't ends with a /, it will be the destination file name
  elif [[ $type == "ERR" && "${dst: -1}" != "/" ]]; then
    dst="$dst"

  #if dst doesn't exists and ends with a /, it will be the destination folder
  elif [[ $type == "ERR" && "${dst: -1}" == "/" ]]; then
    local filename
    filename=$(basename "$src")
    dst="$dst/$filename"

  #If dst it's a directory, it will be the destination folder
  elif [[ $type == "DIR" ]]; then
    local filename
    filename=$(basename "$src")
    dst="$dst/$filename"
  fi

  #It's a directory
  if [[ -d $src ]]; then
    echo "It's dir"
    db_upload_dir "$src" "$dst"

  #It's a file
  elif [[ -e $src ]]; then
    echo "It's file"
    db_upload_file "$src" "$dst"

  #Unsupported object...
  else
    print " > Skipping not regular file \"$src\"\n"
  fi
}

#Generic upload wrapper around db_chunked_upload_file and db_simple_upload_file
#The final upload function will be choosen based on the file size
#$1 = Local source file
#$2 = Remote destination file
function db_upload_file() {
  local file_src file_dst file_size basefile_dst type
  file_src=$(normalize_path "$1")
  file_dst=$(normalize_path "$2")

  shopt -s nocasematch

  #Checking not allowed file names
  basefile_dst=$(basename "$file_dst")
  if [[ $basefile_dst == "thumbs.db" || $basefile_dst == "desktop.ini" || $basefile_dst == ".ds_store" || $basefile_dst == "icon\r" || $basefile_dst == ".dropbox" || $basefile_dst == ".dropbox.attr" ]] \
    ; then
    print " > Skipping not allowed file name \"$file_dst\"\n"
    return
  fi

  shopt -u nocasematch

  #Checking file size
  file_size=$(file_size "$file_src")

  #Checking if the file already exists
  type=$(db_stat "$file_dst")
  if [[ $type != "ERR" && $SKIP_EXISTING_FILES == 1 ]]; then
    print " > Skipping already existing file \"$file_dst\"\n"
    return
  fi

  # Checking if the file has the correct check sum
  if [[ $type != "ERR" ]]; then
    local sha_src sha_dst
    sha_src=$(db_sha_local "$file_src")
    sha_dst=$(db_sha "$file_dst")
    if [[ $sha_src == $sha_dst && $sha_src != "ERR" ]]; then
      print "> Skipping file \"$file_src\", file exists with the same hash\n"
      return
    fi
  fi

  if [[ $file_size -gt 157286000 ]]; then
    #If the file is greater than 150Mb, the chunked_upload API will be used
    db_chunked_upload_file "$file_src" "$file_dst"
  else
    db_simple_upload_file "$file_src" "$file_dst"
  fi

}

#Simple file upload
#$1 = Local source file
#$2 = Remote destination file
function db_simple_upload_file() {
  local file_src file_dst curl_parameters line_cr
  file_src=$(normalize_path "$1")
  file_dst=$(normalize_path "$2")

  if [[ $SHOW_PROGRESSBAR == 1 && $QUIET == 0 ]]; then
    curl_parameters="--progress-bar"
    line_cr="\n"
  else
    curl_parameters="-L -s"
    line_cr=""
  fi

  print " > Uploading \"$file_src\" to \"$file_dst\"... $line_cr"
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES $curl_parameters -X POST -i --globoff -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"path\": \"$file_dst\",\"mode\": \"overwrite\",\"autorename\": true,\"mute\": false}" --header "Content-Type: application/octet-stream" --data-binary @"$file_src" "$API_UPLOAD_URL"
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
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
function db_chunked_upload_file() {
  local file_src file_dst curl_parameters file_size offset upload_id upload_error chunk_params \
    session_id chunk_number number_of_chunk
  file_src=$(normalize_path "$1")
  file_dst=$(normalize_path "$2")

  if [[ $SHOW_PROGRESSBAR == 1 && $QUIET == 0 ]]; then
    VERBOSE=1
    curl_parameters="--progress-bar"
  else
    VERBOSE=0
    curl_parameters="-L -s"
  fi

  file_size=$(file_size "$file_src")
  offset=0
  upload_id=""
  upload_error=0
  chunk_params=""

  ## Ceil division
  ((number_of_chunk = (file_size / 1024 / 1024 + CHUNK_SIZE - 1) / CHUNK_SIZE))

  if [[ $VERBOSE == 1 ]]; then
    print " > Uploading \"$file_src\" to \"$file_dst\" by $number_of_chunk chunks ...\n"
  else
    print " > Uploading \"$file_src\" to \"$file_dst\" by $number_of_chunk chunks "
  fi

  #Starting a new upload session
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"close\": false}" --header "Content-Type: application/octet-stream" --data-binary @/dev/null "$API_CHUNKED_UPLOAD_START_URL" 2>/dev/null
  check_http_response $?

  session_id=$(sed -n 's/{"session_id": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")

  chunk_number=1
  #Uploading chunks...
  while [[ $offset != "$file_size" ]]; do
    local offset_mb chunk_real_size
    ((offset_mb = offset / 1024 / 1024))
    #Create the chunk
    dd if="$file_src" of="$CHUNK_FILE" bs=1048576 skip="$offset_mb" count="$CHUNK_SIZE" 2>/dev/null
    chunk_real_size=$(file_size "$CHUNK_FILE")

    if [[ $VERBOSE == 1 ]]; then
      print " >> Uploading chunk $chunk_number of $number_of_chunk\n"
    fi

    #Uploading the chunk...
    echo >"$RESPONSE_FILE"
    ensure_accesstoken
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST $curl_parameters --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"cursor\": {\"session_id\": \"$session_id\",\"offset\": $offset},\"close\": false}" --header "Content-Type: application/octet-stream" --data-binary @"$CHUNK_FILE" "$API_CHUNKED_UPLOAD_APPEND_URL"
    #check_http_response $? not needed, because we have to retry the request in case of error

    #Check
    if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
      ((offset = offset + chunk_real_size))
      upload_error=0
      if [[ $VERBOSE != 1 ]]; then
        print "."
      fi
      ((chunk_number = chunk_number + 1))
    else
      if [[ $VERBOSE != 1 ]]; then
        print "*"
      fi
      ((upload_error = upload_error + 1))

      #On error, the upload is retried for max 3 times
      if [[ $upload_error -gt 2 ]]; then
        print " FAILED\n"
        print "An error occurred requesting /chunked_upload\n"
        ERROR_STATUS=1
        return
      fi
    fi

  done

  upload_error=0

  #Commit the upload
  while (true); do

    echo >"$RESPONSE_FILE"
    ensure_accesstoken
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"cursor\": {\"session_id\": \"$session_id\",\"offset\": $offset},\"commit\": {\"path\": \"$file_dst\",\"mode\": \"overwrite\",\"autorename\": true,\"mute\": false}}" --header "Content-Type: application/octet-stream" --data-binary @/dev/null "$API_CHUNKED_UPLOAD_FINISH_URL" 2>/dev/null
    #check_http_response $? not needed, because we have to retry the request in case of error

    #Check
    if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
      upload_error=0
      break
    else
      print "*"
      ((upload_error = upload_error + 1))

      #On error, the commit is retried for max 3 times
      if [[ $upload_error -gt 2 ]]; then
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
function db_upload_dir() {
  local dis_src dir_dst
  dis_src=$(normalize_path "$1")
  dir_dst=$(normalize_path "$2")

  #Creatig remote directory
  db_mkdir "$dir_dst"

  for file in "$dis_src/"*; do
    db_upload "$file" "$dir_dst"
  done
}

#Generic download wrapper
#$1 = Remote source file/dir
#$2 = Local destination file/dir
function db_download() {
  local src dst dest_dir basedir out_file type src_req
  src=$(normalize_path "$1")
  dst=$(normalize_path "$2")

  type=$(db_stat "$src")

  #It's a directory
  if [[ $type == "DIR" ]]; then

    #If the dst folder is not specified, I assume that is the current directory
    if [[ $dst == "" ]]; then
      dst="."
    fi

    #Checking if the destination directory exists
    if [[ ! -d $dst ]]; then
      basedir=""
    else
      basedir=$(basename "$src")
    fi

    dest_dir=$(normalize_path "$dst/$basedir")
    print " > Downloading folder \"$src\" to \"$dest_dir\"... \n"

    if [[ ! -d "$dest_dir" ]]; then
      print " > Creating local directory \"$dest_dir\"... "
      mkdir -p "$dest_dir"
      #Check
      if [[ $? -eq 0 ]]; then
        print "DONE\n"
      else
        print "FAILED\n"
        ERROR_STATUS=1
        return
      fi
    fi

    if [[ $src == "/" ]]; then
      src_req=""
    else
      src_req="$src"
    fi

    out_file=$(db_list_outfile "$src_req")
    if [ $? -ne 0 ]; then
      # When db_list_outfile fail, the error message is out_file
      print "$out_file\n"
      ERROR_STATUS=1
      return
    fi

    #For each entry...
    while read -r line; do
      local file meta type size
      file=${line%:*}
      meta=${line##*:}
      type=${meta%;*}
      size=${meta#*;}

      #Removing unneeded /
      file=${file##*/}

      if [[ $type == "file" ]]; then
        db_download_file "$src/$file" "$dest_dir/$file"
      elif [[ $type == "folder" ]]; then
        db_download "$src/$file" "$dest_dir"
      fi

    done <"$out_file"

    rm -fr "$out_file"

  #It's a file
  elif [[ $type == "FILE" ]]; then

    #Checking dst
    if [[ $dst == "" ]]; then
      dst=$(basename "$src")
    fi

    #If the destination is a directory, the file will be download into
    if [[ -d $dst ]]; then
      dst="$dst/$src"
    fi

    db_download_file "$src" "$dst"

  #Doesn't exists
  else
    print " > No such file or directory: $src\n"
    ERROR_STATUS=1
    return
  fi
}

#Simple file download
#$1 = Remote source file
#$2 = Local destination file
function db_download_file() {
  local file_src file_dst curl_parameters line_cr
  file_src=$(normalize_path "$1")
  file_dst=$(normalize_path "$2")

  if [[ $SHOW_PROGRESSBAR == 1 && $QUIET == 0 ]]; then
    curl_parameters="-L --progress-bar"
    line_cr="\n"
  else
    curl_parameters="-L -s"
    line_cr=""
  fi

  #Checking if the file already exists
  if [[ -e $file_dst && $SKIP_EXISTING_FILES == 1 ]]; then
    print " > Skipping already existing file \"$file_dst\"\n"
    return
  fi

  # Checking if the file has the correct check sum
  type=$(db_stat "$file_dst")
  if [[ $type != "ERR" ]]; then
    local sha_src sha_dst
    sha_src=$(db_sha "$file_src")
    sha_dst=$(db_sha_local "$file_dst")
    if [[ $sha_src == $sha_dst && $sha_src != "ERR" ]]; then
      print "> Skipping file \"$file_src\", file exists with the same hash\n"
      return
    fi
  fi

  #Creating the empty file, that for two reasons:
  #1) In this way I can check if the destination file is writable or not
  #2) Curl doesn't automatically creates files with 0 bytes size
  dd if=/dev/zero of="$file_dst" count=0 2>/dev/null
  if [[ $? != 0 ]]; then
    print " > Error writing file $file_dst: permission denied\n"
    ERROR_STATUS=1
    return
  fi

  print " > Downloading \"$file_src\" to \"$file_dst\"... $line_cr"
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES $curl_parameters -X POST --globoff -D "$RESPONSE_FILE" -o "$file_dst" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Dropbox-API-Arg: {\"path\": \"$file_src\"}" "$API_DOWNLOAD_URL"
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    print "DONE\n"
  else
    print "FAILED\n"
    rm -fr "$file_dst"
    ERROR_STATUS=1
    return
  fi
}

#Saveurl
#$1 = url
#$2 = Remote file destination
function db_saveurl() {
  local url file_dst file_name job_id
  url="$1"
  file_dst=$(normalize_path "$2")
  file_name=$(basename "$url")

  print " > Downloading \"$url\" to \"$file_dst\"..."
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$file_dst/$file_name\", \"url\": \"$url\"}" "$API_SAVEURL_URL" 2>/dev/null
  check_http_response $?

  job_id=$(sed -n 's/.*"async_job_id": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
  if [[ $job_id == "" ]]; then
    print " > Error getting the job id\n"
    return
  fi

  #Checking the status
  while (true); do
    local status message
    ensure_accesstoken
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"async_job_id\": \"$job_id\"}" "$API_SAVEURL_JOBSTATUS_URL" 2>/dev/null
    check_http_response $?

    status=$(sed -n 's/{".tag": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
    case $status in

    in_progress)
      print "+"
      ;;

    complete)
      print " DONE\n"
      break
      ;;

    failed)
      print " ERROR\n"
      message=$(sed -n 's/.*"error_summary": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
      print " > Error: $message\n"
      break
      ;;

    esac

    sleep 2

  done
}

#Prints account info
function db_account_info() {
  print "Dropbox Uploader v$VERSION\n\n"
  print " > Getting info... "
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" "$API_ACCOUNT_INFO_URL" 2>/dev/null
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    local name uid email country
    name=$(sed -n 's/.*"display_name": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
    echo -e "\n\nName:\t\t$name"

    uid=$(sed -n 's/.*"account_id": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
    echo -e "UID:\t\t$uid"

    email=$(sed -n 's/.*"email": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
    echo -e "Email:\t\t$email"

    country=$(sed -n 's/.*"country": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
    echo -e "Country:\t$country"

    echo ""

  else
    print "FAILED\n"
    ERROR_STATUS=1
  fi
}

#Prints account space usage info
function db_account_space() {
  print "Dropbox Uploader v$VERSION\n\n"
  print " > Getting space usage info... "
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" "$API_ACCOUNT_SPACE_URL" 2>/dev/null
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    local quota quota_mb used used_mb free_mb
    quota=$(sed -n 's/.*"allocated": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
    ((quota_mb = quota / 1024 / 1024))
    echo -e "\n\nQuota:\t$quota_mb Mb"

    used=$(sed -n 's/.*"used": \([0-9]*\).*/\1/p' "$RESPONSE_FILE")
    ((used_mb = used / 1024 / 1024))
    echo -e "Used:\t$used_mb Mb"

    ((free_mb = $((quota - used)) / 1024 / 1024))
    echo -e "Free:\t$free_mb Mb"

    echo ""

  else
    print "FAILED\n"
    ERROR_STATUS=1
  fi
}

#Account unlink
function db_unlink() {
  local answer
  echo -ne "Are you sure you want unlink this script from your Dropbox account? [y/n]"
  read -r answer
  if [[ $answer == "y" ]]; then
    rm -fr "$CONFIG_FILE"
    echo -ne "DONE\n"
  fi
}

#Delete a remote file
#$1 = Remote file to delete
function db_delete() {
  local file_dst
  file_dst=$(normalize_path "$1")

  print " > Deleting \"$file_dst\"... "
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$file_dst\"}" "$API_DELETE_URL" 2>/dev/null
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    print "DONE\n"
  else
    print "FAILED\n"
    ERROR_STATUS=1
  fi
}

#Move/Rename a remote file
#$1 = Remote file to rename or move
#$2 = New file name or location
function db_move() {
  local file_src file_dst type
  file_src=$(normalize_path "$1")
  file_dst=$(normalize_path "$2")

  type=$(db_stat "$file_dst")

  #If the destination it's a directory, the source will be moved into it
  if [[ $type == "DIR" ]]; then
    local filename
    filename=$(basename "$file_src")
    file_dst=$(normalize_path "$file_dst/$filename")
  fi

  print " > Moving \"$file_src\" to \"$file_dst\" ... "
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"from_path\": \"$file_src\", \"to_path\": \"$file_dst\"}" "$API_MOVE_URL" 2>/dev/null
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    print "DONE\n"
  else
    print "FAILED\n"
    ERROR_STATUS=1
  fi
}

#Copy a remote file to a remote location
#$1 = Remote file to rename or move
#$2 = New file name or location
function db_copy() {
  local file_src file_dst type

  file_src=$(normalize_path "$1")
  file_dst=$(normalize_path "$2")
  type=$(db_stat "$file_dst")

  #If the destination it's a directory, the source will be copied into it
  if [[ $type == "DIR" ]]; then
    local filename
    filename=$(basename "$file_src")
    file_dst=$(normalize_path "$file_dst/$filename")
  fi

  print " > Copying \"$file_src\" to \"$file_dst\" ... "
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"from_path\": \"$file_src\", \"to_path\": \"$file_dst\"}" "$API_COPY_URL" 2>/dev/null
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    print "DONE\n"
  else
    print "FAILED\n"
    ERROR_STATUS=1
  fi
}

#Create a new directory
#$1 = Remote directory to create
function db_mkdir() {
  local dir_dst
  dir_dst=$(normalize_path "$1")

  print " > Creating Directory \"$dir_dst\"... "
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$dir_dst\"}" "$API_MKDIR_URL" 2>/dev/null
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    print "DONE\n"
  elif grep -q "{\"error_summary\": \"path/conflict/folder/" "$RESPONSE_FILE"; then
    print "ALREADY EXISTS\n"
  else
    print "FAILED\n"
    ERROR_STATUS=1
  fi
}

#List a remote folder and returns the path to the file containing the output
#$1 = Remote directory
#$2 = Cursor (Optional)
function db_list_outfile() {
  local dir_dst has_more cursor out_file

  dir_dst="$1"
  has_more="false"
  cursor=""

  if [[ -n "$2" ]]; then
    cursor="$2"
    has_more="true"
  fi

  out_file="$TMP_DIR/du_tmp_out_$RANDOM"

  while (true); do

    if [[ $has_more == "true" ]]; then
      ensure_accesstoken
      $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"cursor\": \"$cursor\"}" "$API_LIST_FOLDER_CONTINUE_URL" 2>/dev/null
    else
      ensure_accesstoken
      $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$dir_dst\",\"include_media_info\": false,\"include_deleted\": false,\"include_has_explicit_shared_members\": false}" "$API_LIST_FOLDER_URL" 2>/dev/null
    fi

    check_http_response $?

    has_more=$(sed -n 's/.*"has_more": *\([a-z]*\).*/\1/p' "$RESPONSE_FILE")
    cursor=$(sed -n 's/.*"cursor": *"\([^"]*\)".*/\1/p' "$RESPONSE_FILE")

    #Check
    if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
      local dir_content
      #Extracting directory content [...]
      #and replacing "}, {" with "}\n{"
      #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
      dir_content=$(sed -n 's/.*: \[{\(.*\)/\1/p' "$RESPONSE_FILE" | sed 's/}, *{/}\
    {/g')

      #Converting escaped quotes to unicode format
      echo "$dir_content" | sed 's/\\"/\\u0022/' >"$TEMP_FILE"

      #Extracting files and subfolders
      while read -r line; do
        local file type size
        file=$(echo "$line" | sed -n 's/.*"path_display": *"\([^"]*\)".*/\1/p')
        type=$(echo "$line" | sed -n 's/.*".tag": *"\([^"]*\).*/\1/p')
        size=$(convert_bytes "$(echo "$line" | sed -n 's/.*"size": *\([0-9]*\).*/\1/p')")

        echo -e "$file:$type;$size" >>"$out_file"

      done <"$TEMP_FILE"

      if [[ $has_more == "false" ]]; then
        break
      fi

    else
      return
    fi

  done

  echo "$out_file"
}

#List remote directory
#$1 = Remote directory
function db_list() {
  local dir_dst out_file padding

  dir_dst=$(normalize_path "$1")

  print " > Listing \"$dir_dst\"... "

  if [[ "$dir_dst" == "/" ]]; then
    dir_dst=""
  fi

  out_file=$(db_list_outfile "$dir_dst")
  if [ -z "$out_file" ]; then
    print "FAILED\n"
    ERROR_STATUS=1
    return
  else
    print "DONE\n"
  fi

  #Looking for the biggest file size
  #to calculate the padding to use
  padding=0
  while read -r line; do
    local file meta size
    file=${line%:*}
    meta=${line##*:}
    size=${meta#*;}

    if [[ ${#size} -gt $padding ]]; then
      padding=${#size}
    fi
  done <"$out_file"

  #For each entry, printing directories...
  while read -r line; do
    local file meta type size
    file=${line%:*}
    meta=${line##*:}
    type=${meta%;*}
    size=${meta#*;}

    #Removing unneeded /
    file=${file##*/}

    if [[ $type == "folder" ]]; then
      file=$(echo -e "$file")
      $PRINTF " [D] %-${padding}s %s\n" "$size" "$file"
    fi

  done <"$out_file"

  #For each entry, printing files...
  while read -r line; do
    local file meta type size
    file=${line%:*}
    meta=${line##*:}
    type=${meta%;*}
    size=${meta#*;}

    #Removing unneeded /
    file=${file##*/}

    if [[ $type == "file" ]]; then
      file=$(echo -e "$file")
      $PRINTF " [F] %-${padding}s %s\n" "$size" "$file"
    fi

  done <"$out_file"

  rm -fr "$out_file"
}

#Longpoll remote directory only once
#$1 = Timeout
#$2 = Remote directory
function db_monitor_nonblock() {
  local timeout dir_dst
  timeout=$1
  dir_dst=$(normalize_path "$2")

  if [[ "$dir_dst" == "/" ]]; then
    dir_dst=""
  fi

  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$dir_dst\",\"include_media_info\": false,\"include_deleted\": false,\"include_has_explicit_shared_members\": false}" "$API_LIST_FOLDER_URL" 2>/dev/null
  check_http_response $?

  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    local cursor changes
    cursor=$(sed -n 's/.*"cursor": *"\([^"]*\)".*/\1/p' "$RESPONSE_FILE")

    ensure_accesstoken
    $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Content-Type: application/json" --data "{\"cursor\": \"$cursor\",\"timeout\": ${timeout}}" "$API_LONGPOLL_FOLDER" 2>/dev/null
    check_http_response $?

    if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
      changes=$(sed -n 's/.*"changes" *: *\([a-z]*\).*/\1/p' "$RESPONSE_FILE")
    else
      local error_msg
      error_msg=$(grep "Error in call" "$RESPONSE_FILE")
      print "FAILED to longpoll (http error): $error_msg\n"
      ERROR_STATUS=1
      return 1
    fi

    # NOTE: This code will never check, the variable CHANGES should be in upper function scope
    if [[ -z "$changes" ]]; then
      print "FAILED to longpoll (unexpected response)\n"
      ERROR_STATUS=1
      return 1
    fi

    if [ "$changes" == "true" ]; then
      local out_file
      out_file=$(db_list_outfile "$dir_dst" "$cursor")

      if [ -z "$out_file" ]; then
        print "FAILED to list changes\n"
        ERROR_STATUS=1
        return
      fi

      #For each entry, printing directories...
      while read -r line; do
        local file meta type size
        file=${line%:*}
        meta=${line##*:}
        type=${meta%;*}
        size=${meta#*;}

        #Removing unneeded /
        file=${file##*/}

        if [[ $type == "folder" ]]; then
          file=$(echo -e "$file")
          $PRINTF " [D] %s\n" "$file"
        elif [[ $type == "file" ]]; then
          file=$(echo -e "$file")
          $PRINTF " [F] %s %s\n" "$size" "$file"
        elif [[ $type == "deleted" ]]; then
          file=$(echo -e "$file")
          $PRINTF " [-] %s\n" "$file"
        fi

      done <"$out_file"

      rm -fr "$out_file"
    fi

  else
    ERROR_STATUS=1
    return 1
  fi

}

#Longpoll continuously remote directory
#$1 = Timeout
#$2 = Remote directory
function db_monitor() {
  local timeout dir_dst
  timeout=$1
  dir_dst=$(normalize_path "$2")

  while (true); do
    db_monitor_nonblock "$timeout" "$2"
  done
}

#Share remote file
#$1 = Remote file
function db_share() {
  local file_dst
  file_dst=$(normalize_path "$1")

  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$file_dst\",\"settings\": {\"requested_visibility\": \"public\"}}" "$API_SHARE_URL" 2>/dev/null
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    local share_link
    print " > Share link: "
    share_link=$(sed -n 's/.*"url": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
    echo "$share_link"
  else
    get_Share "$file_dst"
  fi
}

#Query existing shared link
#$1 = Remote file
function get_Share() {
  local file_dst
  file_dst=$(normalize_path "$1")
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"$file_dst\",\"direct_only\": true}" "$API_SHARE_LIST"
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    local share_link
    print " > Share link: "
    share_link=$(sed -n 's/.*"url": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
    echo "$share_link"
  else
    local message
    print "FAILED\n"
    message=$(sed -n 's/.*"error_summary": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
    print " > Error: $message\n"
    ERROR_STATUS=1
  fi
}

#Search on Dropbox
#$1 = query
function db_search() {
  local query dir_content
  query="$1"

  print " > Searching for \"$query\"... "

  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-Type: application/json" --data "{\"path\": \"\",\"query\": \"$query\",\"start\": 0,\"max_results\": 1000,\"mode\": \"filename\"}" "$API_SEARCH_URL" 2>/dev/null
  check_http_response $?

  #Check
  if grep -q "^HTTP/[12].* 200" "$RESPONSE_FILE"; then
    print "DONE\n"
  else
    print "FAILED\n"
    ERROR_STATUS=1
  fi

  #Extracting directory content [...]
  #and replacing "}, {" with "}\n{"
  #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
  dir_content=$(sed 's/}, *{/}\
{/g' "$RESPONSE_FILE")

  #Converting escaped quotes to unicode format
  echo "$dir_content" | sed 's/\\"/\\u0022/' >"$TEMP_FILE"

  #Extracting files and subfolders
  rm -fr "$RESPONSE_FILE"
  while read -r line; do
    local file type size
    file=$(echo "$line" | sed -n 's/.*"path_display": *"\([^"]*\)".*/\1/p')
    type=$(echo "$line" | sed -n 's/.*".tag": *"\([^"]*\).*/\1/p')
    size=$(convert_bytes "$(echo "$line" | sed -n 's/.*"size": *\([0-9]*\).*/\1/p')")

    echo -e "$file:$type;$size" >>"$RESPONSE_FILE"

  done <"$TEMP_FILE"

  #Looking for the biggest file size
  #to calculate the padding to use
  local padding=0
  while read -r line; do
    local file meta size
    file=${line%:*}
    meta=${line##*:}
    size=${meta#*;}

    if [[ ${#size} -gt $padding ]]; then
      padding=${#size}
    fi
  done <"$RESPONSE_FILE"

  #For each entry, printing directories...
  while read -r line; do
    local file meta type size
    file=${line%:*}
    meta=${line##*:}
    type=${meta%;*}
    size=${meta#*;}

    if [[ $type == "folder" ]]; then
      file=$(echo -e "$file")
      $PRINTF " [D] %-${padding}s %s\n" "$size" "$file"
    fi

  done <"$RESPONSE_FILE"

  #For each entry, printing files...
  while read -r line; do
    local file meta type size

     file=${line%:*}
     meta=${line##*:}
     type=${meta%;*}
     size=${meta#*;}

    if [[ $type == "file" ]]; then
      file=$(echo -e "$file")
      $PRINTF " [F] %-${padding}s %s\n" "$size" "$file"
    fi

  done <"$RESPONSE_FILE"

}

#Query the sha256-dropbox-sum of a remote file
#see https://www.dropbox.com/developers/reference/content-hash for more information
#$1 = Remote file
function db_sha() {
  local file type sha256
  file=$(normalize_path "$1")

  if [[ $file == "/" ]]; then
    echo "ERR"
    return
  fi

  #Checking if it's a file or a directory and get the sha-sum
  ensure_accesstoken
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES -X POST -L -s --show-error --globoff -i -o "$RESPONSE_FILE" --header "Authorization: Bearer $OAUTH_ACCESS_TOKEN" --header "Content-type: application/json" --data "{\"path\": \"$file\"}" "$API_METADATA_URL" 2>/dev/null
  check_http_response $?

  type=$(sed -n 's/{".tag": *"*\([^"]*\)"*.*/\1/p' "$RESPONSE_FILE")
  if [[ $type == "folder" ]]; then
    echo "ERR"
    return
  fi

  sha256=$(sed -n 's/.*"content_hash": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
  echo "$sha256"
}

#Query the sha256-dropbox-sum of a local file
#see https://www.dropbox.com/developers/reference/content-hash for more information
#$1 = Local file
function db_sha_local() {
  local file file_size offset skip sha_concat sha sha_hex
  file=$(normalize_path "$1")
  file_size=$(file_size "$file")
  offset=0
  skip=0
  sha_concat=""

  which shasum >/dev/null
  if [[ $? -ne 0 ]]; then
    echo "ERR"
    return
  fi

  while [[ $offset -lt "$file_size" ]]; do
    dd if="$file" of="$CHUNK_FILE" bs=4194304 skip=$skip count=1 2>/dev/null
    sha=$(shasum -a 256 "$CHUNK_FILE" | awk '{print $1}')
    sha_concat="${sha_concat}${sha}"

    ((offset = offset + 4194304))
    ((skip = skip + 1))
  done

  if [[ "$(uname -s)" == "Darwin" ]]; then
    # sed for macOS will give an error "bad flag in substitute command: 'I'"
    # when using the original syntax. This option works instead.
    sha_hex=$(echo "$sha_concat" | sed 's/\([0-9A-Fa-f]\{2\}\)/\\x\1/g')
  else
    sha_hex=$(echo "$sha_concat" | sed 's/\([0-9A-F]\{2\}\)/\\x\1/gI')
  fi

  echo -ne "$sha_hex" | shasum -a 256 | awk '{print $1}'
}


################
#### SETUP  ####
################

#CHECKING FOR AUTH FILE
if [[ -e $CONFIG_FILE ]]; then

  # Test the config file
  TEST_SOURCE="$(source "${CONFIG_FILE}" 2>&1 >/dev/null)"
  if [[ $? -eq 0 ]]; then
    #Loading data...
    source "$CONFIG_FILE" 2>/dev/null
  else
    echo -ne "Error, config file ${CONFIG_FILE} contains invalid syntax\n"
    echo -ne "Error details:\n"
    echo "${TEST_SOURCE}"
    mv "$CONFIG_FILE" "$CONFIG_FILE".old
    exit 1
  fi

  #Checking if it's still a v1 API configuration file
  if [[ $CONFIGFILE_VERSION != "2.0" ]]; then
    echo -ne "The config file contains the old deprecated v1 or v2 oauth tokens.\n"
    echo -ne "Please run again the script and follow the configuration wizard. The old configuration file has been backed up to $CONFIG_FILE.old\n"
    mv "$CONFIG_FILE" "$CONFIG_FILE".old
    exit 1
  fi

  #Checking loaded data
  if [[ $OAUTH_APP_KEY == "" || $OAUTH_APP_SECRET == "" || $OAUTH_REFRESH_TOKEN == "" ]]; then
    echo -ne "Error loading data from $CONFIG_FILE...\n"
    echo -ne "It is recommended to run $0 unlink\n"
    remove_temp_files
    exit 1
  fi

#NEW SETUP...
else
  echo -ne "\n This is the first time you run this script, please follow the instructions:\n\n"
  echo -ne "(note: Dropbox will change their API from 30.9.2021.\n"
  echo -ne "When using dropbox_uploader.sh configured in the past with the old API, have a look at README.md, before continue.)\n\n"
  echo -ne " 1) Open the following URL in your Browser, and log in using your account: $APP_CREATE_URL\n"
  echo -ne " 2) Click on \"Create App\", then select \"Choose an API: Scoped Access\"\n"
  echo -ne " 3) \"Choose the type of access you need: App folder\"\n"
  echo -ne " 4) Enter the \"App Name\" that you prefer (e.g. MyUploader$RANDOM$RANDOM$RANDOM), must be unique\n\n"
  echo -ne " Now, click on the \"Create App\" button.\n\n"
  echo -ne " 5) Now the new configuration is opened, switch to tab \"permissions\" and check \"files.metadata.read/write\" and \"files.content.read/write\"\n"
  echo -ne " Now, click on the \"Submit\" button.\n\n"
  echo -ne " 6) Now to tab \"settings\" and provide the following information:\n"

  echo -ne " App key: "
  read -r OAUTH_APP_KEY

  echo -ne " App secret: "
  read -r OAUTH_APP_SECRET

  URL="${API_OAUTH_AUTHORIZE}?client_id=${OAUTH_APP_KEY}&token_access_type=offline&response_type=code"
  echo -ne "  Open the following URL in your Browser and allow suggested permissions: ${URL}\n"
  echo -ne " Please provide the access code: "
  read -r ACCESS_CODE

    echo -ne "\n > App key: \'${OAUTH_APP_KEY}\'\n"
    echo -ne " > App secret: \'${OAUTH_APP_SECRET}\'\n"
    echo -ne " > Access code: \'${ACCESS_CODE}\'. Looks ok? [y/N]: "
    read -r answer
    if [[ $answer != "y" ]]; then
        remove_temp_files
        exit 1
    fi
  $CURL_BIN $CURL_ACCEPT_CERTIFICATES $API_OAUTH_TOKEN -d code=$ACCESS_CODE -d grant_type=authorization_code -u $OAUTH_APP_KEY:$OAUTH_APP_SECRET -o "$RESPONSE_FILE" 2>/dev/null
  check_http_response $?

  OAUTH_REFRESH_TOKEN=$(sed -n 's/.*"refresh_token": "\([^"]*\).*/\1/p' "$RESPONSE_FILE")
echo "OAUTH_REFRESH_TOKEN: ${OAUTH_REFRESH_TOKEN}"
  {
    echo "CONFIGFILE_VERSION=2.0"
    echo "OAUTH_APP_KEY=$OAUTH_APP_KEY"
    echo "OAUTH_APP_SECRET=$OAUTH_APP_SECRET"
    echo "OAUTH_REFRESH_TOKEN=$OAUTH_REFRESH_TOKEN"
  } >"$CONFIG_FILE"

  echo "   The configuration has been saved."

  remove_temp_files
  exit 0
fi

# GET ACCESS TOKEN
ensure_accesstoken

################
#### START  ####
################

COMMAND="${*:$OPTIND:1}"
ARG1="${*:$OPTIND+1:1}"
ARG2="${*:$OPTIND+2:1}"
ARGS_NUM=$#

((ARGNUM = ARGS_NUM - OPTIND))

#CHECKING PARAMS VALUES
case $COMMAND in

upload)

  if [[ $ARGNUM -lt 2 ]]; then
    usage
  fi

  FILE_DST="${*:$#:1}"
  for ((i = OPTIND + 1; i < $#; i++)); do
    FILE_SRC="${*:$i:1}"
    db_upload "$FILE_SRC" "/$FILE_DST"
  done

  ;;

download)

  if [[ $ARGNUM -lt 1 ]]; then
    usage
  fi

  FILE_SRC="$ARG1"
  FILE_DST="$ARG2"

  db_download "/$FILE_SRC" "$FILE_DST"

  ;;

saveurl)

  if [[ $ARGNUM -lt 1 ]]; then
    usage
  fi

  URL=$ARG1
  FILE_DST="$ARG2"

  db_saveurl "$URL" "/$FILE_DST"

  ;;

share)

  if [[ $ARGNUM -lt 1 ]]; then
    usage
  fi

  FILE_DST="$ARG1"

  db_share "/$FILE_DST"

  ;;

info)

  db_account_info

  ;;

space)

  db_account_space

  ;;

delete | remove)

  if [[ $ARGNUM -lt 1 ]]; then
    usage
  fi

  FILE_DST="$ARG1"

  db_delete "/$FILE_DST"

  ;;

move | rename)

  if [[ $ARGNUM -lt 2 ]]; then
    usage
  fi

  FILE_SRC="$ARG1"
  FILE_DST="$ARG2"

  db_move "/$FILE_SRC" "/$FILE_DST"

  ;;

copy)

  if [[ $ARGNUM -lt 2 ]]; then
    usage
  fi

  FILE_SRC="$ARG1"
  FILE_DST="$ARG2"

  db_copy "/$FILE_SRC" "/$FILE_DST"

  ;;

mkdir)

  if [[ $ARGNUM -lt 1 ]]; then
    usage
  fi

  DIR_DST="$ARG1"

  db_mkdir "/$DIR_DST"

  ;;

search)

  if [[ $ARGNUM -lt 1 ]]; then
    usage
  fi

  QUERY=$ARG1

  db_search "$QUERY"

  ;;

list)

  DIR_DST="$ARG1"

  #Checking DIR_DST
  if [[ $DIR_DST == "" ]]; then
    DIR_DST="/"
  fi

  db_list "/$DIR_DST"

  ;;

monitor)

  DIR_DST="$ARG1"
  TIMEOUT=$ARG2

  #Checking DIR_DST
  if [[ $DIR_DST == "" ]]; then
    DIR_DST="/"
  fi

  print " > Monitoring \"$DIR_DST\" for changes...\n"

  if [[ -n $TIMEOUT ]]; then
    db_monitor_nonblock "$TIMEOUT" "/$DIR_DST"
  else
    db_monitor 60 "/$DIR_DST"
  fi

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

if [[ $ERROR_STATUS -ne 0 ]]; then
  echo "Some error occurred. rerun the script with \"-d\" option and check the output and logfile: $RESPONSE_FILE."
fi

exit $ERROR_STATUS
