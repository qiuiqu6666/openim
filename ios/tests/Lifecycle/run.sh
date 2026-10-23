#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/scene-invite-tests.XXXXXX")
trap 'rm -rf "$build"' EXIT HUP INT TERM
xcrun swiftc -swift-version 5 \
  "$root/ios/Runner/Lifecycle/FriendInvitePendingState.swift" \
  "$root/ios/tests/Lifecycle/FriendInviteTests.swift" \
  -o "$build/invite-tests"
"$build/invite-tests"
