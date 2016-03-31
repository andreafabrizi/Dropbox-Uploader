#!/usr/bin/env bash

dropup="/opt/Dropbox-Uploader/dropbox_uploader.sh" #Path to your Dropbox-Uploader installation

chosen=$1

path_dropbox=${chosen#*Dropbox/}

share_link_text=$($dropup share $path_dropbox)

cut_share_link=${share_link_text#*: }

echo $cut_share_link | xclip -selection "clipboard"

