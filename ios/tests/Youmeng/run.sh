#!/bin/sh
# macOS: executes the production tunnel against local scripted TCP relays.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/youmeng-tests.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  "$root/ios/Runner/Youmeng/GameShieldClient.swift" \
  "$root/ios/Runner/Youmeng/TunnelConnection.swift" \
  "$root/ios/tests/Youmeng/TunnelRecoveryTests.swift" \
  -o "$build/tunnel-tests"
"$build/tunnel-tests"
