# Thunar Dropbox: a plugin for Dropbox Uploader

A simple extension to [Dropbox Uploader](https://github.com/andreafabrizi/Dropbox-Uploader) that provides a convenient method to share your Dropbox files with one click!

## Installation

1. Install [Dropbox Uploader](https://github.com/andreafabrizi/Dropbox-Uploader)
2. Install `xclip` package
3. Move Dropbox-Uploader to your desired path (for example /opt/Dropbox-Uploader/)
4. Run `plugins/thunar/install.sh` script (chmod +x install.sh and thunar-dropbox.sh if necessary) & restart thunar
5. This plugin works if you have your Dropbox folder located in standard path ($HOME/Dropbox). If not, create a symlink (ln -s).

## How to use

**1. In order to get a link, right click on a file and choose "Dropbox: share link" option.**

![thunar-dropbox01](https://cloud.githubusercontent.com/assets/11591703/14191395/f833afda-f797-11e5-96db-b779e1919248.jpg)

**2. You should see a notify-send popup with information about ready-to-share link.**

![thunar-dropbox02](https://cloud.githubusercontent.com/assets/11591703/14191398/f856abc0-f797-11e5-9b14-93e5b75411a1.jpg)

**3. Your link has been copied to your clipboard!**

_NB:_ it takes about one-two seconds to generate the link, so don't immediately try to paste the link!

_Tested on Xubuntu 15.10 with Thunar 1.6.6_

## Requirements

* [Dropbox Uploader](https://github.com/andreafabrizi/Dropbox-Uploader)
* xclip

## To do

* ~~copy to clipboard~~
* ~~create custom action automatically~~
* ~~if not in Dropbox folder, copy to Dropbox/Public and share~~
* ~~notify alert that making link was successful~~
* troubleshooting

## Known drawbacks

* sharing files / directories **with spaces in names does not work**
* you can select one file / directory at the same time 
* for some unknown reason Dropbox-Uploader sometimes gives "FAILED" result instead of a link. This is npt a script specific issue and in such scenario I encourage to simply try again.

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
