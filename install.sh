#!/usr/bin/env bash
#
# Dropbox Uploader and Dropbox Shell installer
#
# Copyright (C) 2014 Stefanos Kalantzis <steve.tcmg@gmail.com>
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


##############################################
####             VARIABLES                ####
##############################################
installation_dir=~/bin
installation_method=copy
dropbox_uploader_command_name=dropbox-client
dropbox_shell_command_name=dropbox-shell
downloaded_dir=`pwd`

##############################################
####               INPUT                  ####
##############################################
echo -e "You will be asked to verify everything before proceeding with the installation at the end of this section.\n"
agree="hW8u1F"
while [ "$agree" != "y" ]; do
	if [ "$agree" == "hW8u1F" ]; then
		echo -e "On all questions, just press enter for the default."
	else
		echo -e "On all questions, just press enter for the previous answer."
	fi
	echo -e "\nChoose installation directory:
	1 ~/bin (default)
	2 /usr/local/bin
	3 /usr/bin
	or enter custom directory"
	if [ "$agree" != "hW8u1F" ]; then
		echo "previous answer: $installation_dir"
	fi
	read -p "choose [ 1 / 2 / 3 / custom ] : " chosen_dir

	if [ ! "X$chosen_dir" == "X" ]; then
		if [ "$chosen_dir" == "1" ]; then
			installation_dir=~/bin
		elif [ "$chosen_dir" == "2" ]; then
			installation_dir=/usr/local/bin
		elif [ "$chosen_dir" == "3" ]; then
			installation_dir=/usr/bin
		else
			installation_dir=$chosen_dir
		fi
	fi
	eval installation_dir=$installation_dir

	correct=0
	while [ $correct -eq 0 ]; do
		echo -e "\nChoose installation method:
		1 copy (default)
		2 link [shortcut] - if you choose this, the current directory with its files must not be deleted"
		if [ "$agree" != "hW8u1F" ]; then
			echo "previous answer: $installation_method"
		fi
		read -p "choose [ 1 / 2 ] : " chosen_install_method

		if [ "X$chosen_install_method" == "X" ]; then
			correct=1
		elif [ "$chosen_install_method" == "1" ]; then
			installation_method=copy
			correct=1
		elif [ "$chosen_install_method" == "2" ]; then
			installation_method=link
			correct=1
		fi
	done

	correct=0
	while [ $correct -eq 0 ]; do
		echo -e "\nChoose command name for dropbox_uploader.sh
	1 dropbox-client (default)
	2 dropbox_uploader
	3 dropbox_uploader.sh
	or enter custom name"
		if [ "$agree" != "hW8u1F" ]; then
			echo "previous answer: $chosen_name_uploader"
		fi
		read -p "choose [ 1 / 2 / 3 / custom ] : " chosen_name_uploader

		if [ ! "X$chosen_name_uploader" == "X" ]; then
			if [ "$chosen_name_uploader" == "1" ]; then
				dropbox_uploader_command_name=dropbox-client
			elif [ "$chosen_name_uploader" == "2" ]; then
				dropbox_uploader_command_name=dropbox_uploader
			elif [ "$chosen_name_uploader" == "3" ]; then
				dropbox_uploader_command_name=dropbox_uploader.sh
			else
				dropbox_uploader_command_name=$chosen_name_uploader
			fi
		fi
		command -v $dropbox_uploader_command_name >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "$dropbox_uploader_command_name already exists in PATH. please choose again..."
		else
			correct=1
		fi
	done

	correct=0
	while [ $correct -eq 0 ]; do
		echo -e "\nChoose command name for dropShell.sh
	1 dropbox-shell (default)
	2 dropShell
	3 dropShell.sh
	or enter custom name"
		if [ "$agree" != "hW8u1F" ]; then
			echo "previous answer: $chosen_name_shell"
		fi
		read -p "choose [ 1 / 2 / 3 / custom ] : " chosen_name_shell

		if [ ! "X$chosen_name_shell" == "X" ]; then
			if [ "$chosen_name_shell" == "1" ]; then
				dropbox_shell_command_name=dropbox-shell
			elif [ "$chosen_name_shell" == "2" ]; then
				dropbox_shell_command_name=dropShell
			elif [ "$chosen_name_shell" == "3" ]; then
				dropbox_shell_command_name=dropShell.sh
			else
				dropbox_shell_command_name=$chosen_name_shell
			fi
		fi
		command -v $dropbox_shell_command_name >/dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "$dropbox_shell_command_name already exists in PATH. please choose again..."
		else
			correct=1
		fi
	done

	echo -e "\nGiven Configuration:
installation directory: $installation_dir
installation method: $installation_method
command name to be used for dropbox_uploader.sh: $dropbox_uploader_command_name
command name to be used for dropShell.sh: $dropbox_shell_command_name\n"
	read -p "Do you agree? [y/n] : " agree
done

##############################################
####               CHECKS                 ####
##############################################
if [ -e "$installation_dir" ]; then
	if [ -d "$installation_dir" ]; then
		if [ ! -w "$installation_dir" ]; then
			chmod u+w "$installation_dir"
			if [ $? -ne 0 ]; then
				echo "Directory $installation_dir is not writeable"
				exit 1
			fi
		fi
	else
		echo "$installation_dir is not a directory"
		exit 2
	fi
else
	mkdir "$installation_dir"
	if [ $? -ne 0 ]; then
		echo "Could not create directory $installation_dir"
		exit 3
	fi
	chmod u+w "$installation_dir"
	if [ $? -ne 0 ]; then
		echo "Directory $installation_dir is not writeable"
		exit 1
	fi
fi

do_write_to_profile=0
if [ $(echo $PATH | grep -c $installation_dir) -eq 0 ]; then
	echo "$installation_dir was not found in PATH. Will try to add it via ~/.profile"
	if [ -e ~/.profile ]; then
		if [ -w ~/.profile ]; then
			do_write_to_profile=1
		else
			chmod u+w ~/.profile
			if [ $? -ne 0 ]; then
				echo "File ~/.profile is not writeable"
				exit 4
			fi
			do_write_to_profile=1
		fi
	else
		echo "~/.profile does not exist. Please insert the following code to your shell's profile or if you don't have one, inside the ~/.profile file."
		echo "
# Inserted by installation script of https://github.com/Kidlike/Dropbox-Uploader
if [ -d \"$installation_dir\" ] ; then
	PATH=\"$installation_dir:$PATH\"
fi
"
		exit 5
	fi
fi

if [ $do_write_to_profile -eq 1 ]; then
	cat >> ~/.profile <<EOF

# Inserted by installation script of https://github.com/Kidlike/Dropbox-Uploader
if [ -d "$installation_dir" ] ; then
	PATH="$installation_dir:\$PATH"
fi
EOF
	echo "...done"
fi


##############################################
####              INSTALL                 ####
##############################################
echo -e "\n\n================== Installing ==================\n"
if [ "$installation_method" == "link" ]; then
	ACTION="ln -sf"
else
	ACTION="cp -p"
fi

if [ -e dropShell.sh.orig ]; then
	mv dropShell.sh.orig dropShell.sh
fi
if [ -e dropShell-fix-path.patch.orig ]; then
	mv dropShell-fix-path.patch.orig dropShell-fix-path.patch
fi

sed -i.orig "s/@{dropbox_uploader_command_name}/$dropbox_uploader_command_name/g" dropShell-fix-path.patch
patch -b dropShell.sh < dropShell-fix-path.patch

echo "installing dropbox_uploader.sh to $installation_dir/$dropbox_uploader_command_name"
eval $ACTION "`pwd`/dropbox_uploader.sh" "$installation_dir/$dropbox_uploader_command_name"
echo "installing dropShell.sh to $installation_dir/$dropbox_shell_command_name"
eval $ACTION "`pwd`/dropShell.sh" "$installation_dir/$dropbox_shell_command_name"

if [ "$installation_method" == "copy" ]; then
	mv dropShell.sh.orig dropShell.sh
	mv dropShell-fix-path.patch.orig dropShell-fix-path.patch
else
	echo -e "\n!!! If you delete any files from this directory the commands will stop working!"
	echo -e "!!! You can use the copy installation method to avoid this (run ./uninstall first)"
fi

echo -e "\nstoring used configuration options for reference in ~/.dropbox_uploader_installed.conf"
cat > ~/.dropbox_uploader_installed.conf <<EOF
installation_dir=$installation_dir
installation_method=$installation_method
dropbox_uploader_command_name=$dropbox_uploader_command_name
dropbox_shell_command_name=$dropbox_shell_command_name
downloaded_dir=$downloaded_dir
EOF
