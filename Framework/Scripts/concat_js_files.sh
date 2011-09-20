#!/bin/bash
ERLANG_DSTDIR="${CONFIGURATION_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/CouchbaseResources"

cd ../../vendor/couchdb/share/server

cat util.js emonk_app.js > $ERLANG_DSTDIR/emonk_app.js
cat util.js emonk_mapred.js > $ERLANG_DSTDIR/emonk_mapred.js
