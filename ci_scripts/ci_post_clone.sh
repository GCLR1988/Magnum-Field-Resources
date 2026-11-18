#!/bin/sh
# Xcode Cloud supplies the three Dropbox values as secret workflow variables.
set +x
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /usr/bin/xcrun swift "$script_dir/generate_credentials.swift"
