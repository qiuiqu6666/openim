#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/network-path-tests.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
xcrun swiftc -swift-version 5 \
  "$root/local_plugin/flutter_openim_sdk/ios/Classes/Connectivity/IMNetworkPathPolicy.swift" \
  "$root/ios/tests/Connectivity/NetworkPathTests.swift" \
  -o "$build/network-path-tests"
"$build/network-path-tests"
