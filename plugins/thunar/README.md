# Thunar Dropbox: a plugin for Dropbox Uploader

A simple extension to [Dropbox Uploader](https://github.com/andreafabrizi/Dropbox-Uploader) that provides a convenient method to share your Dropbox files with one click!


## How to use

1. Edit thunar-dropbox.sh and insert proper path to *dropbox_uploader.sh* as a *dropup* variable
2. Create [custom action](https://www.linux.com/learn/tutorials/440846-extend-xfces-thunar-file-manager-with-custom-actions) in Thunar, choose the name, icon and set command as: <br>
`/path/to/thunar-dropbox.sh %f`
3. Set "File Pattern" to * (asterisk), in "Appears if selection contains" - tick all boxes
4. In order to share a file (or directory), right click and choose your custom action
5. Your link has been copied to your clipboard!

_NB:_ it takes about one-two seconds to generate the link, so don't immediately try to paste the link!

## Requirements

* [Dropbox Uploader](https://github.com/andreafabrizi/Dropbox-Uploader)
* xclip

## To do

* ~~copy to clipboard~~
* create custom action automatically (custom icon?)
* if not in Dropbox folder, copy to Dropbox/Public and share

## About the author

* github: [mDfRg](https://github.com/mDfRg)
* website: [mindefrag.net](http://mindefrag.net/)
* community: [stackoverflow](http://stackoverflow.com/users/4697442/mdfrg)

---

## About Dropbox Uploader

Dropbox Uploader is a **BASH** script which can be used to upload, download, delete, list files (and more!) from **Dropbox**, an online file sharing, synchronization and backup service. 

It's written in BASH scripting language and only needs **cURL**.

**Why use this script?**

* **Portable:** It's written in BASH scripting and only needs *cURL* (curl is a tool to transfer data from or to a server, available for all operating systems and installed by default in many linux distributions).
* **Secure:** It's not required to provide your username/password to this script, because it uses the official Dropbox API for the authentication process. 

Please refer to the &lt;Wiki&gt;(https://github.com/andreafabrizi/Dropbox-Uploader/wiki) for tips and additional information about this project. The Wiki is also the place where you can share your scripts and examples related to Dropbox Uploader.

**Features**

* Cross platform
* Support for the official Dropbox API
* No password required or stored
* Simple step-by-step configuration wizard
* Simple and chunked file upload
* File and recursive directory download
* File and recursive directory upload
* Shell wildcard expansion (only for upload)
* Delete/Move/Rename/Copy/List files
* **Create share link**
<%%>: Required param


## Donations

 If you want to support this project, please consider donating:
 * PayPal: andrea.fabrizi@gmail.com
 * BTC: 1JHCGAMpKqUwBjcT3Kno9Wd5z16K6WKPqG
