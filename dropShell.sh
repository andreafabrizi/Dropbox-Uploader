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

DU="./dropbox_uploader.sh"

SHELL_HISTORY=~/.dropshell_history
DU_OPT="-q"
BIN_DEPS="id readlink ls basename"
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
    DU=$(readlink -m "$DU")
fi

#Returns the current user
function get_current_user
{
    id -nu
}

function normalize_path
{
    readlink -m "$1"
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

while (true); do

    #Reading command from shell
    read -e -p "$username@DropBox:$CWD$ " input

    #Tokenizing command
    tokens=( $input )
    cmd=${tokens[0]}
    arg1=${tokens[1]}
    arg2=${tokens[2]}

    #Saving command in the history file
    history -s "$input"
    history -w "$SHELL_HISTORY"

    case $cmd in

        ls)
            
            #Listing current dir
            if [ -z "$arg1" ]; then
                $DU $DU_OPT list "$CWD"

            #Listing $arg1
            else

                #Relative or absolute path?
                if [ ${arg1:0:1} == "/" ]; then
                    $DU $DU_OPT list $(normalize_path "$arg1")
                else
                    $DU $DU_OPT list $(normalize_path "$CWD/$arg1")
                fi

                #Checking for errors
                if [ $? -ne 0 ]; then
                    echo -e "ls: cannot access '$arg1': No such file or directory"
                fi
            fi

        ;;

        cd)

            OLD_CWD=$CWD

            if [ -z "$arg1" ]; then
                CWD="/"
            else
                arg1=${input:3} #All the arguments
            fi

            CWD=$(normalize_path "$CWD/$arg1/")
            $DU $DU_OPT list "$CWD" > /dev/null
    
            #Checking for errors
            if [ $? -ne 0 ]; then
                echo -e "cd: $arg1: No such file or directory"
                CWD=$OLD_CWD
            fi

        ;;

        pwd)

            echo $CWD

        ;;

        get)

            if [ ! -z "$arg1" ]; then

                #Relative or absolute path?
                if [ ${arg1:0:1} == "/" ]; then
                    $DU $DU_OPT download $(normalize_path "$arg1") "$arg2"
                else
                    $DU $DU_OPT download $(normalize_path "$CWD/$arg1") "$arg2"
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

        ;;

        put)

            if [ ! -z "$arg1" ]; then
        
                #Relative or absolute path?
                if [ "${arg2:0:1}" == "/" ]; then
                    $DU $DU_OPT upload "$arg1" $(normalize_path "$arg2")
                else
                    $DU $DU_OPT upload "$arg1" $(normalize_path "$CWD/$arg2")
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

        ;;

        rm)

            if [ ! -z "$arg1" ]; then

                #Relative or absolute path?
                if [ ${arg1:0:1} == "/" ]; then
                    $DU $DU_OPT remove $(normalize_path "$arg1")
                else
                    $DU $DU_OPT remove $(normalize_path "$CWD/$arg1")
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

        ;;

        mkdir)

            if [ ! -z "$arg1" ]; then

                #Relative or absolute path?
                if [ ${arg1:0:1} == "/" ]; then
                    $DU $DU_OPT mkdir $(normalize_path "$arg1")
                else
                    $DU $DU_OPT mkdir $(normalize_path "$CWD/$arg1")
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

        ;;

        mv)

            if [ ! -z "$arg1" -a ! -z "$arg2" ]; then

                #SRC relative or absolute path?
                if [ ${arg1:0:1} == "/" ]; then
                    SRC="$arg1"
                else
                    SRC="$CWD/$arg1"
                fi

                #DST relative or absolute path?
                if [ ${arg2:0:1} == "/" ]; then
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

        ;;

        lls)

            ls -l

        ;;

        lpwd)

            pwd

        ;;

        lcd)

            cd "$arg1"

        ;;

        help)

            echo -e "Availabe commands: ls, cd, pwd, get, put, rm, mkdir, mv, lls, lpwd, lcd, help, exit\n"

        ;;

        quit|exit)

            exit 0

        ;;

        *)
            echo -ne "Unknown command: $cmd\n"
        ;;
    esac
done

