#!/bin/bash

DU=./dropbox_uploader.sh

function check_exit
{
    if [ $? -ne 0 ]; then
        echo " Error!!!"
        exit 1
    else
        echo " Passed"
    fi
}

#Creating garbage data
echo -ne " - Creating garbage data...\n"
rm -fr "testData"
mkdir -p "testData"
dd if=/dev/urandom of="testData/file 1.txt" bs=1M count=3
dd if=/dev/urandom of="testData/file 2 ù.txt" bs=1M count=5
mkdir -p "testData/recurse"
dd if=/dev/urandom of="testData/recurse/file 3.txt" bs=1M count=1
dd if=/dev/urandom of="testData/recurse/test_Ü.txt" bs=1M count=1
mkdir -p "testData/recurse/dir 1/"
dd if=/dev/urandom of="testData/recurse/dir 1/file 4.txt" bs=1M count=1
mkdir -p "testData/recurse/dir 1/dir 3/"
dd if=/dev/urandom of="testData/recurse/dir 1/dir 3/file 5.txt" bs=1M count=1
mkdir -p "testData/recurse/dir 2/"

rm -fr recurse

#Rmdir
echo -ne " - Remove remote directory..."
$DU -q remove du_tests
echo ""

#Mkdir
echo -ne " - Make remote directory..."
$DU -q mkdir du_tests
check_exit

#Simple upload
echo -ne " - Simple file upload..."
$DU -q upload "testData/file 1.txt" du_tests
check_exit

#Checking with list
echo -ne " - Checking file..."
$DU -q list du_tests | grep "file 1.txt" > /dev/null
check_exit

#Simple upload 2
echo -ne " - Simple file upload with special chars..."
$DU -q upload testData/file\ 2* du_tests
check_exit

#Checking with list
echo -ne " - Checking file..."
$DU -q list du_tests | grep "file 2 ù.txt" > /dev/null
check_exit

#Recursive directory upload
echo -ne " - Recursive directory upload..."
$DU -q upload testData/recurse du_tests
check_exit

#Recursive directory download
echo -ne " - Recursive directory download..."
$DU -q download du_tests/recurse
check_exit

#Checking the downloaded dir
echo -ne " - Checking the downloaded dir..."
diff -r recurse testData/recurse/
check_exit

#Again, recursive directory download
echo -ne " - Again recursive directory download..."
$DU -q download du_tests/recurse
check_exit

#Again, checking the downloaded dir
echo -ne " - Checking the downloaded dir..."
diff -r recurse testData/recurse/
check_exit

rm -fr "recurse"
rm -fr "testData"

#Rmdir
echo -ne " - Remove remote directory..."
$DU -q remove du_tests
check_exit
