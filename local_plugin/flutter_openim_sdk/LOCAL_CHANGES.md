# Project-owned OpenIM adapter

Source: the published `flutter_openim_sdk 3.8.3+hotfix.12` package. Dart APIs and the adapter package version are preserved; the Core version is independent.

- Both platforms consume the same locked `native_sdk/patch15/ios-core-source/` at `v3.8.3-patch.15+recovery.13`. The directory name is retained for compatibility. This release adds continuous recovery checkpoints, initialization retries, empty-history recovery, durable delivery notifications, visible-range revalidation and fair scheduling; readseq2 and recall fixes remain included.
- Android resolves the local Maven coordinate from `native_sdk/patch15/manifest.json` (currently `io.openim:core-sdk:3.8.3-patch15-recovery.13`). Its `preBuild` validates the shared source, version and AAR receipt/hash. The adapter implements patch.15's three user-command callbacks with the same event names as iOS and logs the actual JNI Core version at initialization.
- iOS expects the same version through `Frameworks/OpenIMCore.xcframework`. Run `native_sdk/patch15/build-ios.sh` on macOS with Xcode, Go 1.24.0 and Python 3. It tests the locked Core, builds device arm64 and simulator arm64/x86_64, and installs the Framework together with `recovery-verification.json`. Minimum iOS is 13; this app targets iOS 15.
- CocoaPods installation and every subsequent plugin compilation verify the iOS receipt and source/binary hashes. Prepare the new Framework and update Pods before opening the app in Xcode. `CORE_PYTHON` can select Python for the Gradle/Pods guards. `fetch-ios.ps1` only obtains an unpatched comparison binary and cannot prepare a recovery release.
- Generated binaries are ignored by Git. A fresh checkout must run the corresponding native build script before the app build. See `native_sdk/patch15/README.md` for commands and validation status. Android recovery.13 AAR/APK builds passed; iOS recovery.13 requires Mac build and device validation by the user.

Upstream license remains in `LICENSE`. Do not edit the shared Pub cache.
