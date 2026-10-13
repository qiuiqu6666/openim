#!/bin/bash
# Build the same patched Core as Android; publish only after bind succeeds.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$root/../.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS with Xcode is required.' >&2; exit 1; }
go_bin="${GO:-$(command -v go)}"
export PATH="$(dirname "$go_bin"):$PATH"
export GOTOOLCHAIN=local
[[ "$("$go_bin" version)" == *' go1.24.0 '* ]] || { echo 'Use Go 1.24.0 to match Android.' >&2; exit 1; }
xcrun --sdk iphoneos --show-sdk-path >/dev/null
mkdir -p "$root/artifacts"
work="$(mktemp -d "$root/artifacts/ios-build.XXXXXX")"
echo "Build directory: $work"
export GOBIN="$work/tools"
export PATH="$GOBIN:$PATH"
read -r commit tag mobile version < <(python3 - "$root" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
m = json.loads((root / 'manifest.json').read_text())
assert hashlib.sha256((root / m['patch']).read_bytes()).hexdigest() == m['patch_sha256'], 'Patch hash mismatch'
print(m['commit'], m['tag'], m['android']['gomobile'], m['android']['sdk_version'])
PY
)
git clone --quiet --depth 1 --branch "$tag" https://github.com/openimsdk/openim-sdk-core.git "$work/source"
cd "$work/source"
[[ "$(git rev-parse HEAD)" == "$commit" ]] || { echo 'Unexpected upstream commit.' >&2; exit 1; }
git apply --check "$root/0001-background-message-recovery.patch"
git apply "$root/0001-background-message-recovery.patch"
"$go_bin" install "golang.org/x/mobile/cmd/gomobile@$mobile"
"$go_bin" install "golang.org/x/mobile/cmd/gobind@$mobile"
"$go_bin" get "golang.org/x/mobile@$mobile"
CGO_ENABLED=0 "$go_bin" test -mod=mod ./pkg/common ./pkg/network ./internal/interaction ./internal/conversation_msg -count=1 -timeout=120s
# Apple bind uses the Xcode toolchain directly. Do not run gomobile init:
# that command installs gobind@latest and defeats the pinned tool version.
go_path="$("$go_bin" env GOPATH)"
mkdir -p "${go_path%%:*}/pkg/gomobile"
CGO_ENABLED=1 gomobile bind -target=ios,iossimulator -iosversion=13.0 -trimpath \
  -ldflags "-s -w -X github.com/openimsdk/openim-sdk-core/v3/version.Version=$version" \
  -o "$work/OpenIMCore.xcframework" ./open_im_sdk/ ./open_im_sdk_callback/
python3 - "$root" "$work" <<'PY'
import hashlib, json, pathlib, plistlib, sys
root, work = map(pathlib.Path, sys.argv[1:])
m = json.loads((root / 'manifest.json').read_text())
framework = work / 'OpenIMCore.xcframework'
info = plistlib.loads((framework / 'Info.plist').read_bytes())
assert len(info['AvailableLibraries']) >= 2
hashes = {}
for lib in info['AvailableLibraries']:
    binary = framework / lib['LibraryIdentifier'] / lib['LibraryPath'] / 'OpenIMCore'
    data = binary.read_bytes()
    assert m['android']['sdk_version'].encode() in data, 'Missing recovery version'
    hashes[str(binary.relative_to(framework))] = hashlib.sha256(data).hexdigest()
(work / 'verification.json').write_text(json.dumps({
    'commit': m['commit'], 'patch_sha256': m['patch_sha256'],
    'sdk_version': m['android']['sdk_version'], 'go_version': '1.24.0',
    'gomobile': m['android']['gomobile'], 'framework_sha256': hashes,
    'core_tests': 'passed', 'device_runtime': 'not tested'
}, indent=2) + '\n')
PY
destination="$repo/local_plugin/flutter_openim_sdk/ios/Frameworks"
mkdir -p "$destination"
cp -R "$work/OpenIMCore.xcframework" "$work/install-OpenIMCore.xcframework"
# Preserve the previous binary for rollback instead of deleting it.
if [[ -e "$destination/OpenIMCore.xcframework" ]]; then
  mv "$destination/OpenIMCore.xcframework" "$work/previous-OpenIMCore.xcframework"
fi
mv "$work/install-OpenIMCore.xcframework" "$destination/OpenIMCore.xcframework"
echo "Installed $version; evidence: $work/verification.json"
echo 'Next: ./tool/flutterw build ios --release --no-codesign'
