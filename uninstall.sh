#!/usr/bin/env bash
#
# Dropbox Uploader and Dropbox Shell uninstaller
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


# stored configuration options from installation
#installation_dir=
#installation_method=
#dropbox_uploader_command_name=
#dropbox_shell_command_name=
#downloaded_dir=

if [ -r ~/.dropbox_uploader_installed.conf ]; then
	echo -e "Reading used installation config options from ~/.dropbox_uploader_installed.conf\n"
	for line in $(cat ~/.dropbox_uploader_installed.conf); do
		eval $line
	done
else
	echo "~/.dropbox_uploader_installed.conf does not exist. Assuming it is not installed."
	exit
fi

echo -e "Removing installed files...\n"

eval rm -vf "$installation_dir/$dropbox_shell_command_name"
eval rm -vf "$installation_dir/$dropbox_uploader_command_name"
eval rm -vf "~/.dropbox_uploader_installed.conf"

if [ "$installation_method" == "link" ]; then
	echo -e "\nRestoring original files"
	eval mv -v "$downloaded_dir/dropShell.sh.orig" "$downloaded_dir/dropShell.sh"
	eval mv -v "$downloaded_dir/dropShell-fix-path.patch.orig" "$downloaded_dir/dropShell-fix-path.patch"
fi

echo -e "\n...done"

