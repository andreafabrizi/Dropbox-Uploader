#!/usr/bin/env bash
#
# DropShell
#
# Copyright (C) 2013 Andrea Fabrizi <andrea.fabrizi@gmail.com>
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

#Looking for dropbox uploader
if [ -f "./dropbox_uploader.sh" ]; then
    DU="./dropbox_uploader.sh"
else
    DU=$(which dropbox_uploader.sh)
    if [ $? -ne 0 ]; then
        echo "Dropbox Uploader not found!"
        exit 1
    fi
fi

#For MacOSX, install coreutils (which includes greadlink)
# $brew install coreutils
if [ "${OSTYPE:0:6}" == "darwin" ]; then
    READLINK="greadlink"
else
    READLINK="readlink"
fi

SHELL_HISTORY=~/.dropshell_history
DU_OPT="-q"
BIN_DEPS="id $READLINK ls basename ls pwd cut"
VERSION="0.1"

umask 077

#Dependencies check
for i in $BIN_DEPS; do
    which $i > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "Error: Required program could not be found: $i"
        exit 1
    fi
done

#Check DropBox Uploader
if [ ! -f "$DU" ]; then
    echo "DropBox Uploader not found: $DU"
    echo "Please change the 'DU' variable according to the DropBox Uploader location."
    exit 1
else
    DU=$($READLINK -m "$DU")
fi

#Returns the current user
function get_current_user
{
    id -nu
}

function normalize_path
{
    $READLINK -m "$1"
}

################
#### START  ####
################

echo -e "DropShell v$VERSION"
echo -e "The Intractive DropBox SHELL"
echo -e "Andrea Fabrizi - andrea.fabrizi@gmail.com\n"
echo -e "Type help for the list of the available commands.\n"

history -r "$SHELL_HISTORY"
username=$(get_current_user)

#Initial Working Directory
CWD="/"

function sh_ls
{
    local arg1="$1"

    #Listing current dir
    if [ -z "$arg1" ]; then
        $DU $DU_OPT list "$CWD"

    #Listing $arg1
    else

        #Relative or absolute path?
        if [ "${arg1:0:1}" == "/" ]; then
            $DU $DU_OPT list "$(normalize_path "$arg1")"
        else
            $DU $DU_OPT list "$(normalize_path "$CWD/$arg1")"
        fi

        #Checking for errors
        if [ $? -ne 0 ]; then
            echo -e "ls: cannot access '$arg1': No such file or directory"
        fi
    fi
}

function sh_cd
{
    local arg1="$1"

    OLD_CWD=$CWD

    if [ -z "$arg1" ]; then
        CWD="/"
    else
        arg1="${input:3}" #All the arguments
    fi

    CWD=$(normalize_path "$CWD/$arg1/")
    $DU $DU_OPT list "$CWD" > /dev/null

    #Checking for errors
    if [ $? -ne 0 ]; then
        echo -e "cd: $arg1: No such file or directory"
        CWD="$OLD_CWD"
    fi
}

function sh_get
{
    local arg1="$1"
    local arg2="$2"

    if [ ! -z "$arg1" ]; then

        #Relative or absolute path?
        if [ "${arg1:0:1}" == "/" ]; then
            $DU $DU_OPT download "$(normalize_path "$arg1")" "$arg2"
        else
            $DU $DU_OPT download "$(normalize_path "$CWD/$arg1")" "$arg2"
        fi

        #Checking for errors
        if [ $? -ne 0 ]; then
            echo -e "get: Download error"
        fi

    #args error
    else
        echo -e "get: missing operand"
        echo -e "syntax: get FILE/DIR [LOCAL_FILE/DIR]"
    fi
}

function sh_put
{
    local arg1="$1"
    local arg2="$2"

    if [ ! -z "$arg1" ]; then

        #Relative or absolute path?
        if [ "${arg2:0:1}" == "/" ]; then
            $DU $DU_OPT upload "$arg1" "$(normalize_path "$arg2")"
        else
            $DU $DU_OPT upload "$arg1" "$(normalize_path "$CWD/$arg2")"
        fi

        #Checking for errors
        if [ $? -ne 0 ]; then
            echo -e "put: Upload error"
        fi

    #args error
    else
        echo -e "put: missing operand"
        echo -e "syntax: put FILE/DIR [REMOTE_FILE/DIR]"
    fi
}

function sh_rm
{
    local arg1="$1"

    if [ ! -z "$arg1" ]; then

        #Relative or absolute path?
        if [ "${arg1:0:1}" == "/" ]; then
            $DU $DU_OPT remove "$(normalize_path "$arg1")"
        else
            $DU $DU_OPT remove "$(normalize_path "$CWD/$arg1")"
        fi

        #Checking for errors
        if [ $? -ne 0 ]; then
            echo -e "rm: cannot remove '$arg1'"
        fi

    #args error
    else
        echo -e "rm: missing operand"
        echo -e "syntax: rm FILE/DIR"
    fi
}

function sh_mkdir
{
    local arg1="$1"

    if [ ! -z "$arg1" ]; then

        #Relative or absolute path?
        if [ "${arg1:0:1}" == "/" ]; then
            $DU $DU_OPT mkdir "$(normalize_path "$arg1")"
        else
            $DU $DU_OPT mkdir "$(normalize_path "$CWD/$arg1")"
        fi

        #Checking for errors
        if [ $? -ne 0 ]; then
            echo -e "mkdir: cannot create directory '$arg1'"
        fi

    #args error
    else
        echo -e "mkdir: missing operand"
        echo -e "syntax: mkdir DIR_NAME"
    fi
}

function sh_mv
{
    local arg1="$1"
    local arg2="$2"

    if [ ! -z "$arg1" -a ! -z "$arg2" ]; then

        #SRC relative or absolute path?
        if [ "${arg1:0:1}" == "/" ]; then
            SRC="$arg1"
        else
            SRC="$CWD/$arg1"
        fi

        #DST relative or absolute path?
        if [ "${arg2:0:1}" == "/" ]; then
            DST="$arg2"
        else
            DST="$CWD/$arg2"
        fi

        $DU $DU_OPT move $(normalize_path "$SRC") $(normalize_path "$DST")

        #Checking for errors
        if [ $? -ne 0 ]; then
            echo -e "mv: cannot move '$arg1' to '$arg2'"
        fi

    #args error
    else
        echo -e "mv: missing operand"
        echo -e "syntax: mv FILE/DIR DEST_FILE/DIR"
    fi
}

function sh_cp
{
    local arg1="$1"
    local arg2="$2"

    if [ ! -z "$arg1" -a ! -z "$arg2" ]; then

        #SRC relative or absolute path?
        if [ "${arg1:0:1}" == "/" ]; then
            SRC="$arg1"
        else
            SRC="$CWD/$arg1"
        fi

        #DST relative or absolute path?
        if [ "${arg2:0:1}" == "/" ]; then
            DST="$arg2"
        else
            DST="$CWD/$arg2"
        fi

        $DU $DU_OPT copy "$(normalize_path "$SRC")" "$(normalize_path "$DST")"

        #Checking for errors
        if [ $? -ne 0 ]; then
            echo -e "cp: cannot copy '$arg1' to '$arg2'"
        fi

    #args error
    else
        echo -e "cp: missing operand"
        echo -e "syntax: cp FILE/DIR DEST_FILE/DIR"
    fi
}


function sh_free
{
    $DU $DU_OPT info | grep "Free:" | cut -f 2
}

function sh_cat
{
    local arg1="$1"

    tmp_cat="/tmp/sh_cat"
    sh_get "$arg1" "$tmp_cat"
    cat "$tmp_cat"
    rm -fr "$tmp_cat"
}

function sh_tokenize
{
    for (( i=1 ; i<=$# ; i++ )); do
        printf "${!i}|"
    done
}

IFS_OLD="$IFS"

while (true); do

    #Reading command from shell
    read -e -p "$username@DropBox:$CWD$ " input
    IFS='|'
    read -ra arg <<< "$( eval sh_tokenize $input )"
    IFS="$IFS_OLD"
    # dbg lines
    # for (( i=0 ; i < ${#arg[@]} ; i++ )); do
    #     echo "arg[$i] = ${arg[$i]}"
    # done
    cmd="${arg[0]}"

    #Saving command in the history file
    history -s "$input"
    history -w "$SHELL_HISTORY"

    case $cmd in

        ls)
            sh_ls "${arg[1]}" "${arg[2]}"
        ;;

        cd)
            sh_cd "${arg[1]}"
        ;;

        pwd)
            echo $CWD
        ;;

        get)
            sh_get "${arg[1]}" "${arg[2]}"
        ;;

        put)
            sh_put "${arg[1]}" "${arg[2]}"
        ;;

        rm)
            sh_rm "${arg[1]}"
        ;;

        mkdir)
            sh_mkdir "${arg[1]}"
        ;;

        mv)
            sh_mv "${arg[1]}" "${arg[2]}"
        ;;

        cp)
            sh_cp "${arg[1]}" "${arg[2]}"
        ;;

        cat)
            sh_cat "${arg[1]}"
        ;;

        free)
            sh_free
        ;;

        lls)
            ls -l
        ;;

        lpwd)
            pwd
        ;;

        lcd)
            cd "${arg[1]}"
        ;;

        help)
            echo -e "Supported commands: ls, cd, pwd, get, put, cat, rm, mkdir, mv, cp, free, lls, lpwd, lcd, help, exit\n"
        ;;

        quit|exit)
            exit 0
        ;;

        *)
            if [ ! -z "$cmd" ]; then
                echo -ne "Unknown command: $cmd\n"
            fi
        ;;
    esac
done

