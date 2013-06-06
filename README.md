# Dropbox Uploader

Dropbox Uploader is a **BASH** script which can be used to upload, download, delete, list files (and more!) from **Dropbox**, an online file sharing, synchronization and backup service. 

It's written in BASH scripting language and only needs **cURL**.

**Why use this script?**

* **Portable:** It's written in BASH scripting and only needs *cURL* (curl is a tool to transfer data from or to a server, available for all operating systems and installed by default in many linux distributions).
* **Secure:** It's not required to provide your username/password to this script, because it uses the official Dropbox API for the authentication process. 

Please refer to the [Wiki](https://github.com/andreafabrizi/Dropbox-Uploader/wiki) for tips and additional information about this project. The Wiki is also the place where you can share your scripts and examples related to Dropbox Uploader.

## Usage

The syntax is quite simple:

```
./dropbox_uploader.sh COMMAND [PARAMETERS]...

[%%]: Required param 
<%%>: Optional param
```

**Available commands:**

* **upload** [LOCAL_FILE/DIR] &lt;REMOTE_FILE/DIR&gt;  
Upload a local file or directory to a remote Dropbox folder.  
If the file is bigger than 150Mb the file is uploaded using small chunks (default 4Mb); 
in this case, if VERBOSE is set to 1, a . (dot) is printed for every chunk successfully uploaded. 
Instead, if an error occurs during the chunk uploading, a * (star) is printed and the upload 
is retried for a maximum of three times.  
Only if the file is smaller than 150Mb, the standard upload API is used, and if VERBOSE is set 
to 1 the default curl progress bar is displayed during the upload process.

* **download** [REMOTE_FILE/DIR] &lt;LOCAL_FILE/DIR&gt;  
Download file or directory from Dropbox to a local folder

* **delete** [REMOTE_FILE/DIR]  
Remove a remote file or directory from Dropbox

* **move** [REMOTE_FILE/DIR] [REMOTE_FILE/DIR]  
Move o rename a remote file or directory

* **mkdir** [REMOTE_DIR]  
Create a remote directory on DropBox

* **list** &lt;REMOTE_DIR&gt;  
List the contents of the remote Dropbox folder

* **share** [REMOTE_FILE]  
Get a public share link for the specified file or directory
 
* **info**  
Print some info about your Dropbox account

* **unlink**  
Unlink the script from your Dropbox account


**Optional parameters:**  
* **-f [FILENAME]**  
Load the configuration file from a specific file

**Examples:**
```bash
    ./dropbox_uploader.sh upload /etc/passwd /myfiles/passwd.old
    ./dropbox_uploader.sh upload /etc/passwd
    ./dropbox_uploader.sh download /backup.zip
    ./dropbox_uploader.sh delete /backup.zip
    ./dropbox_uploader.sh mkdir /myDir/
    ./dropbox_uploader.sh upload "My File.txt" "My File 2.txt"   (File name with spaces...)
    ./dropbox_uploader.sh share "My File.txt"
```

## Tested Environments

* GNU Linux
* FreeBSD 8.3
* MacOSX
* Windows/Cygwin
* Raspberry Pi
* QNAP
* iOS
* OpenWRT

If you have successfully tested this script on others systems or platforms please let me know!


## How to setup a proxy

To use a proxy server, just set the **https_proxy** environment variable:

**Linux:**
```bash
    export HTTP_PROXY_USER=XXXX
    export HTTP_PROXY_PASSWORD=YYYY
    export https_proxy=http://192.168.0.1:8080
```

**BSD:**
```bash
    setenv HTTP_PROXY_USER XXXX
    setenv HTTP_PROXY_PASSWORD YYYY
    setenv https_proxy http://192.168.0.1:8080
```
   
## BASH and Curl installation

**Debian & Ubuntu Linux:**
```bash
    sudo apt-get install bash (Probably BASH is already installed on your system)
    sudo apt-get install curl
```

**BSD:**
```bash
    cd /usr/ports/shells/bash && make install clean
    cd /usr/ports/ftp/curl && make install clean
```

**Cygwin:**  
You need to install these packages:  
* curl
* ca-certificates


**Build cURL from source:**
* Download the source tarball from http://curl.haxx.se/download.html
* Follow the INSTALL instructions
   

## Getting started

The first time you use Dropbox Uploader, you have to run these commands:

```bash
 $chmod +x dropbox_uploader.sh
 $./dropbox_uploader.sh
```
