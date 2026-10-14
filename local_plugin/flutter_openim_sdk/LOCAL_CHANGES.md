# Project-owned OpenIM adapter

Source: the published `flutter_openim_sdk 3.8.3+hotfix.12` package. Dart APIs and the adapter's package version are preserved; the Core version is independent.

- Android uses local Maven coordinate `io.openim:core-sdk:3.8.3-patch15-recovery.12-readseq2`, built from official Core `v3.8.3-patch.15` plus the recovery patch under `native_sdk/patch15`. Group recall processing tolerates unavailable display profiles and delivers the persisted recall before repairing conversation previews. It logs the actual JNI Core version once at initialization.
- Android implements patch.15's three user-command callback methods and forwards them with the same event names already used by the iOS adapter.
- iOS uses `v3.8.3-patch.15+recovery.10` through the vendored `OpenIMCore.xcframework`, built from the same commit and recovery patch as Android. Run `native_sdk/patch15/build-ios.sh` on macOS with Xcode and Go 1.24.0; it checks the patch hash, runs Core tests, and builds device/simulator slices with the pinned gomobile version. The Framework requires iOS 13 or newer; this application already targets iOS 15.
- Run the preparation scripts in `native_sdk/patch15` before building a fresh checkout. Generated native binaries are ignored by Git; their sources, versions and checksums are recorded there.
- After preparing the Framework, run `./tool/flutterw build ios --release --no-codesign` to resolve Pods and validate the app. `fetch-ios.ps1` only prepares the unpatched official binary for comparison; do not use it for recovery releases.

Upstream license remains in `LICENSE`. Do not edit the shared Pub cache.
