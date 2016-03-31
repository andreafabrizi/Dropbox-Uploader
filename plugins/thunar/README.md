# Thunar Dropbox: a plugin for Dropbox Uploader

A simple extension to [Dropbox Uploader](https://github.com/andreafabrizi/Dropbox-Uploader) that provides a convenient method to share your Dropbox files with one click!

## Installation

1. install [Dropbox Uploader](https://github.com/andreafabrizi/Dropbox-Uploader)
2. install `xclip` package
3. move Dropbox-Uploader to your desired path (for example /opt//Dropbox-Uploader/)
4. run plugins/thunar/install.sh script (chmod +x install.sh and thunar-dropbox.sh if necessary)
5. restart thunar

## How to use

1. In order to get a link, right click on a file and choose "Dropbox: share link" option
2. Your link has been copied to your clipboard!

_NB:_ it takes about one-two seconds to generate the link, so don't immediately try to paste the link!

Tested on Xubuntu 15.10 with Thunar 1.6.6

## Requirements

* [Dropbox Uploader](https://github.com/andreafabrizi/Dropbox-Uploader)
* xclip

## To do

* ~~copy to clipboard~~
* ~~create custom action automatically~~
* if not in Dropbox folder, copy to Dropbox/Public and share

## Known drawbacks

* install.sh script might be smoother (sed command not working properly without some workarounds - waiting for help, posted question on [StackExchange](http://unix.stackexchange.com/questions/273366/sed-cannot-insert-if-a-file-ends-with-empty-line))

## About the author of the plugin

* github: [mDfRg](https://github.com/mDfRg)
* website: [mindefrag.net](http://mindefrag.net/)

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
