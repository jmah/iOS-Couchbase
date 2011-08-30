#!/bin/sh
# The 'CouchbaseResources' subfolder of the framework contains Erlang code and other resources
# needed at runtime. Copy it into the app bundle:

# Directory containing the built Couchbase.framework:
COUCHBASE_FRAMEWORK_DIR="${TARGET_BUILD_DIR}/../${CONFIGURATION}-universal"
# The app's Resources directory, where CouchbaseResources will go:
RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

echo "Installing CouchbaseResources into ${RESOURCES_DIR} ..."
rm -rf "${RESOURCES_DIR}/CouchbaseResources"
rsync -a "$COUCHBASE_FRAMEWORK_DIR/Couchbase.framework/CouchbaseResources" "${RESOURCES_DIR}"