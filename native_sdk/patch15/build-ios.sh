#!/bin/bash
# Both native builds consume the shared source selected by manifest.json.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$root/../.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS with Xcode is required.' >&2; exit 1; }
go_bin="${GO:-$(command -v go)}"
export PATH="$(dirname "$go_bin"):$PATH"
export GOTOOLCHAIN=local
export GOWORK=off
export GOFLAGS=-mod=readonly
python3 "$root/prepare_source.py"
read -r go_version mobile version < <(python3 - "$root/manifest.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(m['go_version'], m['gomobile'], m['sdk_version'])
PY
)
[[ "$("$go_bin" version)" == *" go${go_version} "* ]] || { echo "Use Go $go_version." >&2; exit 1; }
xcrun --sdk iphoneos --show-sdk-path >/dev/null
mkdir -p "$root/artifacts"
work="$(mktemp -d "$root/artifacts/ios-build.XXXXXX")"
echo "Build directory: $work"
export GOBIN="$work/tools"
export PATH="$GOBIN:$PATH"
python3 "$root/prepare_source.py" --output "$work/source"
cd "$work/source"
"$go_bin" install "golang.org/x/mobile/cmd/gomobile@$mobile"
"$go_bin" install "golang.org/x/mobile/cmd/gobind@$mobile"
CGO_ENABLED=0 "$go_bin" test ./pkg/logpolicy ./pkg/cache ./internal/user ./open_im_sdk ./pkg/common ./pkg/network ./internal/interaction ./internal/conversation_msg ./internal/relation -count=1 -timeout=120s
CGO_ENABLED=0 "$go_bin" test ./internal/third/file -run '^(TestUploadDeadline|TestUploadHash)' -count=1 -timeout=30s
# CGO=0 skips SQLite transaction/restart tests; run these on the Mac host too.
CGO_ENABLED=1 "$go_bin" test ./internal/group ./internal/interaction ./internal/conversation_msg -count=1 -timeout=120s
CGO_ENABLED=1 "$go_bin" test ./pkg/db -run '^(TestMessageSyncBatch|TestInitialNotificationBootstrap|TestVersionHeaders)' -count=1 -timeout=120s
CGO_ENABLED=0 "$go_bin" test github.com/openimsdk/tools/log -run TestDiagnosticBranding -count=1
CGO_ENABLED=0 "$go_bin" test ./internal/third -run TestBrandedLogPaths -count=1
# Do not run gomobile init, which can replace the pinned gobind with @latest.
go_path="$("$go_bin" env GOPATH)"
mkdir -p "${go_path%%:*}/pkg/gomobile"
CGO_ENABLED=1 gomobile bind -target=ios,iossimulator -iosversion=13.0 -trimpath \
  -ldflags "-s -w -X github.com/openimsdk/openim-sdk-core/v3/version.Version=$version" \
  -o "$work/OpenIMCore.xcframework" ./open_im_sdk/ ./open_im_sdk_callback/
python3 "$root/prepare_source.py" --check-dependencies "$work/source"
python3 "$root/record_artifact.py" ios "$work/OpenIMCore.xcframework" "$work/verification.json"
destination="$repo/local_plugin/flutter_openim_sdk/ios/Frameworks"
mkdir -p "$destination"
cp -R "$work/OpenIMCore.xcframework" "$work/install-OpenIMCore.xcframework"
if [[ -e "$destination/OpenIMCore.xcframework" ]]; then
  mv "$destination/OpenIMCore.xcframework" "$work/previous-OpenIMCore.xcframework"
fi
mv "$work/install-OpenIMCore.xcframework" "$destination/OpenIMCore.xcframework"
cp "$work/verification.json" "$destination/recovery-verification.json"
echo "Installed $version; evidence: $work/verification.json"
echo 'Next: ./tool/flutterw build ios --release --no-codesign'
