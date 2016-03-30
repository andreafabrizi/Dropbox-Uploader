#!/usr/bin/env bash

dropup="/opt/Dropbox-Uploader/dropbox_uploader.sh" #Path to your Dropbox-Uploader installation

chosen=$1

path_dropbox=${chosen#*Dropbox/}

$dropup share $path_dropbox