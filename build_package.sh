#!/bin/sh
######################################################################
##
## Copyright (C) 2003-2014, AVIQ Bulgaria Ltd
##
## Project:       AVTV
## Filename:      build_package.sh
## Description:   Build zip package from installed AVTV
## Arguments:     <target zip directory>
##
######################################################################

# locate root directories
root_dir()
{
	local ROOT_DIR=$(readlink -f "$0")
	while [ ! -f "$ROOT_DIR/build_package.sh" ]; do
		ROOT_DIR=$(dirname $ROOT_DIR)
	done
	echo $ROOT_DIR
}

# returns application version description
# param 1: application git repository
# param 2: version suffix, e.g. build number
app_version()
{
	local git_repo=$1
	local git_ver=$(cd $git_repo && git describe --match "[0-9]*")
	local normal_ver=${git_ver/\-/.}
	local app_ver=${normal_ver/%-*/}
	echo $app_ver
}

# return current base script name
script_name()
{
	local name=$(readlink -f $0)
	name=$(basename $name 2>/dev/null)
	echo $name
} 

# show usage info and exit with failure
usage()
{
	echo "Usage: $(script_name) $1"
	exit 1
}

# process script arguments
TARGET_DIR=$1
[[ -z $TARGET_DIR ]] && usage "<target zip directory>"

ROOT_DIR=$(root_dir)

AVTV_VERSION=$(app_version $ROOT_DIR)
sed -i "s/_VERSION =.*/_VERSION = \"$AVTV_VERSION\";/" $VERSION_FILE lua/avtv/main.lua
ZIP_PACKAGE=avtv-$AVTV_VERSION.zip
zip -r $TARGET_DIR/$ZIP_PACKAGE avtv etc lua node
