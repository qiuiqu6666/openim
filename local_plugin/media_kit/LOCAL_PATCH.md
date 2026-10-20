# Native callback teardown patch

Vendored from media_kit 1.2.1, retaining the upstream MIT LICENSE.
The application selects this copy through dependency_overrides.

The TestFlight 2032 reports abort in DLRT_GetFfiCallbackMetadata while MPV
dispatches events, including events emitted by mpv_terminate_destroy.
Upstream 1.2.1 closes NativeCallable while MPV still holds its function pointer.

This patch unregisters the MPV wakeup callback before closing NativeCallable,
retires the event loop, and awaits any suspended event handler before allowing
native destruction. Queued event loops check that their handler still exists.
Player.dispose now awaits the existing five-second delayed destruction, so its
completion no longer advertises native release prematurely. The delay is retained
for compatibility with the alternate isolate initializer's shutdown behavior.

Regression test: test/platform/media_kit/native_callback_disposal_test.dart in
the application. This exercises an actual Dart FFI listener with a fake MPV API;
iOS device validation with the real MPV binary remains required.
