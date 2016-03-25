# CHANGELOG

## Version 0.16 - 31 Jul 2015
* Add saveurl command to download remote files directly into a dropbox folder
* Fixed issue #174: $DU needs quoting in dropShell
* The share command will now return by default the short url
* Improved portability of the file_size function
* Fixed minor bash compatibility issue in the urlencode function
* Improved normalize_path function and minor fix
* Removed deprecated db_free_quota function

## Version 0.15 - 08 Jun 2015
* Fix issue #163, List only show folders but not files
* Fix issue #168, Share call not returning a share link
* Fix issue #172, list command always return an unnamed dir on an empty directory
* Fix issue #165, Issue with uploading a file to a folder
* Fix issue #162, Uploading a folder to a folder that already exists on dropbox has unexpected behaviour
* Updated setup procedure

## Version 0.14 - 15 Jul 2014
* Fix issue #112, replaced bash condition -f with -e
* Fix issue #117, sed: 1: invalid command code z
* Fix issue #122, Directory upload doesn't work
* Fix issue #132, enhanced cross compatibility for bash conditions

## Version 0.13 - 17 Jan 2014
* Minor languages fixes, based on issue #88
* Fix issue #91, sed take long time to process regexp on big data
* Fix issue #87, second chunked upload fails after successful first
* Fix issue #97, greadlink not selected on OSX Mavericks
* Fix issues #99 and #100: The stat command in OSX 10.9 has no parameter named --format
* Fix issue #99, clarified how to install greadlink (via homebrew) for Mac OS X. Thanks to paultreny
* Improved list command and minor changes
* Fix issue #103, transform Unicode code-points to characters in list command
* Add VERSION output in DEBUG mode
* DropShell: Fixed issue with quoted command parameters
* Fix issue with absolute paths in CD command
* Enhancement request #108: add initial wildcard support in upload command
* Now the destination file/dir for the upload command is mandatory
* Fixed issue listing files/folders names containing quotes

## Version 0.12.1 - 24 Oct 2013
* Fixed unicode problem with special chars in file names
* Fixed problem removing temp files
* Improved detection of configuration error and better handling of http errors
* Updated setup procedure
* Fixed incompatibility with old bash version

## Version 0.12 - 06 Sep 2013
* Fixed problem uploading twice the same directory
* Add checking for not allowed file names
* Handling connection/resolving host errors
* Better error handling
* Converted if condition to BASH native syntax
* Add normalize_path function, to canonicalize paths
* Add -s option to skip existing files when upload/download
* Removed check for free quota on every file upload to improve performance
* Add checks for file permissions before writing/reading files on the local fs
* Add copy function
* Fixed unicode problem in file listing
* A lot of minor changes and improvements

## Version 0.11.9 - 27 Jun 2013
* Add missing -f option in usage
* Add some /dev/null redirects
* Improved error messages
* Improved grep syntax
* Add function to check the cURL exit code
* Improved messages output
* Add new command line options: -q -d -k

## Version 0.11.8 - 05 Jun 2013
* Add move/rename function
* Improved the configuration file management (thanks to Robert G.)
* Updated strings to reflect the new Dropbox "Create App" page
* Add support for download directories
* Add support for upload directories

## Version 0.11.7 - 23 Apr 2013
* Fixed issue with special chars
* Fix for iOS

## Version 0.11.6 - 15 Mar 2013
* Add optional command-line parameter ('-f') to read dropbox configuration from a specific file (thanks to pjv)

## Version 0.11.5 - 22 Gen 2013
* Added the ability to get a share link for a specified file (thanks to camspiers)

## Version 0.11.4 - 17 Gen 2013
* Fix for QNAP compatibility (thanks to Fritz Ferstl)
* Implemented mkdir command (thanks to Joel Maslak)
* Fix for Solaris compatibility

## Version 0.11.3 - 22 Dec 2012:
* Improved list command (thanks to Robert González)
* Fixed problem with unicode characters

## Version 0.11.2 - 14 Nov 2012:
* Added a check for the free quota before uploading a file
* Now the quota informations are displayed in Mb
* Removed urlencode function for incompatibility with older curl versions
* Fixed problem uploading files that contains @ character
* Minor changes

## Version 0.11.1 - 12 Nov 2012:
* As suggested by the DropBox API documentation, the default chunk for chunked uploads is now 4Mb
* Minor changes

## Version 0.11 - 11 Nov 2012:
* Parameterized the curl binary location
* Fix for MacOSX 10.8 (thanks to Ben - www.aquiltforever.com)

## Version 0.10 - 03 Nov 2012:
* Code clean
* Improved urlencode function (thanks to Stefan Trauth * www.stefantrauth.de)
* Added command remove as alias of delete
* Fix for Raspberry PI
* Now if an error occurs during a chunk uploading, the upload is retried for a maximum of three times
* Minor changes
* Tested on Cygwin and MacOSX

## Version 0.9.9 - 24 Oct 2012:
* Added the possibility to choose the access level (App folder o Full Dropbox) during the setup procedure
* Added a check for the BASH shell version
* Fixed problems in listing files/directories with special characters
* Added the option CURL_ACCEPT_CERTIFICATES (see the script source)
* Added back the standard upload function. Now only if the file is greater than 150Mb, the chunked_upload API will be used.
* Fixed compatibility with bsd sed. Tested on FreeBSD, but probably it works on others bsd versions and osx. Let me know!
* Minor changes

## Version 0.9.8 - 03 Oct 2012:
* Implemented chunked upload. Now there is no limit to file size!

## Version 0.9.7 - 14 Sep 2012:
* Fixed bug in listing empty directories

## Version 0.9.6 - 12 Sep 2012:
* Implemented list command
* Minor changes

## Version 0.9.5 - 18 Jul 2012:
* Added a check for the maximum file size allowed by the DropBox API
* Minor changes

## Version 0.9.4 - 19 Mar 2012:
* Implemented delete command
* Minor changes

## Version 0.9.3 - 01 Mar 2012:
* Implemented download command
* Improved info output
* Fixed utime function
* Added dependency check for basename
* The script always returns 1 when errors occurs
* Improved error handling
* Fixed problem with spaces in config file name
* Minor bug fixes

## Version 0.9.2 - 28 Feb 2012:
* Increased security, now any user can create his own Dropbox App

## Version 0.9.1 - 27 Feb 2012:
* Fixed problem with spaces in dst file name

## Version 0.9 - 27 Feb 2012:
* Code rewritten from scratch (CLI changed)
* Improved security and stability using official dropbox API, no more username/password needed!

## Version 0.8.2 - 07 Sep 2011:
* Removed INTERACTIVE_MODE variable (now the progress bar is shown in VERBOSE mode)
* Improved command line interface and error messages
* Minor bug fixes

## Version 0.8.1 - 31 Aug 2011 (by Dawid Ferenczy - www.ferenczy.cz)
* added prompt for the Dropbox password from keyboard, if there is no password
  hardcoded or given as script command line parameter (interactive mode)
* added INTERACTIVE_MODE variable - when set to 1 show CURL progress bar.
  Set to 1 automatically when there is no password hardcoded or given as
  parameter. Controls verbosity of CURL.

## Version 0.7.1 - 10 Mar 2011:
* Minor bug fixes

## Version 0.7 - 10 Mar 2011:
* New command line interface
* Code clean

## Version 0.6 - 11 Gen 2011:
* Fixed issue with spaces in file/forder name

## Version 0.5 - 04 Gen 2011:
* Recursive directory upload

## Version 0.4 - 29 Dec 2010:
* Now works on BSD and MAC
* Interactive prompt for username and password
* Speeded up the uploading process
* Debug mode

## Version 0.3 - 18 Nov 2010:
* Regex updated

## Version 0.2 - 04 Sep 2010:
* Removed dependencies from tempfile
* Code clean

## Version 0.1 - 23 Aug 2010:
* Initial release
