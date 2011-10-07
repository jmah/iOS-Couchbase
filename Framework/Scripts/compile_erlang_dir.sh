#!/bin/bash
#
# Subroutine of build_couchdb.sh that compiles a bunch of Erlang files into a destination dir.
# The current directory is assumed to be the parent of Couchbase.xcodeproj, and the couchdb repo
# is assumed to be checked out into a 'vendor' directory next to the iOS-Couchbase repo, as
# specified by the manifest.
#
# Usage:
#     build_app.sh sourcedirname filelist dstdir [includedir]

set -e  # Bail out if any command returns an error

echo "Building $1 into $3"
mkdir -p "$3"
cd "$1"

if [ $# -ne 4 ]; then
    erlc -W0 +compressed -o "$3" $2
else
    erlc -W0 +compressed -I $4 -o "$3" $2
fi
