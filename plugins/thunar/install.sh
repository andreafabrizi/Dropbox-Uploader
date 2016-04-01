#!/usr/bin/env bash

pack1=`dpkg -l |grep 'xclip' | wc -l`

if [[ $pack1 = 0 ]] ; then
    echo "Please install xclip package before we continue!"
else

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
script_name="thunar-dropbox.sh"
td_sh=$DIR/$script_name

rand1=$((RANDOM%1499999999999999+1400000000000000))
rand2=$((RANDOM%29+1))
rand=$rand1'-'$rand2

uca_xml="$HOME/.config/Thunar/uca.xml"

installed=`cat $uca_xml | grep thunar-dropbox.sh | wc -l`

if [[ $installed != 0 ]]; then
    echo "Plugin already installed!"
else
cat >thunarDropCustAction.txt <<EOL
<action>
    <icon>emblem-shared</icon>
    <name>Dropbox: share link</name>
    <unique-id>$rand</unique-id>
    <command>$td_sh %f</command>
    <description></description>
    <patterns>*</patterns>
    <directories/>
    <audio-files/>
    <image-files/>
    <other-files/>
    <text-files/>
    <video-files/>
</action>
EOL
    echo "Installing plugin..."
    
    if lno=$(sed -n -e '/<\/actions>/=' $uca_xml)
    then let lno=lno-1
         sed -i -e "$lno"'r thunarDropCustAction.txt' $uca_xml
    fi

    rm thunarDropCustAction.txt
    echo "Done!"
fi

fi
