# Project-owned OpenIM adapter

Source: the published `flutter_openim_sdk 3.8.3+hotfix.12` package. Dart APIs and the adapter's package version are preserved; the Core version is independent.

- Android uses local Maven coordinate `io.openim:core-sdk:3.8.3-patch15-recovery.1`, built from official Core `v3.8.3-patch.15` plus the recovery patch under `native_sdk/patch15`. It logs the actual JNI Core version once at initialization.
- Android implements patch.15's three user-command callback methods and forwards them with the same event names already used by the iOS adapter.
- iOS uses the official patch.15 `OpenIMCore.xcframework` through `vendored_frameworks`, replacing the patch.12 Pod dependency. This binary does not include our local recovery patch; compiling that patch requires macOS/Xcode.
- Run the preparation scripts in `native_sdk/patch15` before building a fresh checkout. Generated native binaries are ignored by Git; their sources, versions and checksums are recorded there.
- The existing iOS Pod lock is last resolved on the previous dependency setup. Regenerate it with `pod install` on macOS and build before iOS release. It is not hand-edited to imply successful resolution.

Upstream license remains in `LICENSE`. Do not edit the shared Pub cache.
