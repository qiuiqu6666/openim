# Native Unicode font probe

`unicode_native_probe.dart` is a separate entry point with no OpenIM initialization,
login, message send, backend request, or database write. It uses the current common
widgets and platform fonts. Do not install it using the product's application ID:
that can replace the signed-in application.

## Run in an isolated temporary Flutter package

1. Create a temporary Flutter application with a distinct organization/application
   ID, for example `dev.chat99.unicodeprobe`, outside the product checkout.
2. Copy `unicode_native_probe.dart` to the temporary package's `lib/main.dart`.
3. Copy the shared fixture `test/support/unicode/unicode_samples.dart` directly to
   the temporary package's `lib/unicode_samples.dart`. The tiny re-export file in
   this directory is for running the original entry point from this checkout.
4. Add a path dependency on this checkout's `openim_common`, and
   add `flutter_screenutil: ^5.7.0` and `extended_text_field: ^16.0.0`.
   Apply any necessary existing dependency
   overrides from the product pubspec; do not change product dependencies merely
   to run the probe. Resolve dependencies, then run the temporary application on
   the selected emulator/device.
5. Optional defines are `UNICODE_PROBE_SAMPLE` (zero-based fixture index) and
   `UNICODE_PROBE_DARK=true`. The dropdown and arrows select all structural samples;
   the toolbar toggles light/dark. The live input supports the device keyboard and
   copy/paste; no formatter rewrites it.

`--dart-define=UNICODE_PROBE_AUTORUN=true` cycles every fixture in both themes,
records sequence checks and saves screenshots of its own rendered panels under
`Directory.systemTemp/unicode-probe`. On Android, retrieve only that app's files
using `adb exec-out run-as dev.codex.unicode_native_probe ...`. The log marker
`UNICODE_NATIVE_PROBE_BATCH_COMPLETE` confirms completion. Leave the probe visible
during this short batch; manually changing samples invalidates that batch.

Screenshot the rendered panels and compare the system `Text` reference with
`ChatTextField`, `TextView`, `MatchTextView`, and bold Markdown. Markdown adds an
explicit `A`/`Z` wrapper so leading whitespace with a combining mark is not parsed
as Markdown delimiter spacing. Only display-only Markdown syntax is escaped;
the raw controller value and fixtures remain unchanged.

Logs prefixed `UNICODE_NATIVE_PROBE` contain the platform, theme, sample, input
UTF-16 units, selection/composing offsets, and exact unit comparisons with actual
`ExtendedRenderEditable` (the current input implementation), Flutter
`RenderEditable` (if used), and `RenderParagraph` contents and JSON round trip. Any framework
layout/render error is logged with `UNICODE_NATIVE_PROBE_ERROR`.

## What the probe proves

Successful unit comparisons prove that the rendered text tree retained the raw
Unicode sequence for that input. They do **not** automatically prove a glyph
exists, that a sequence is shaped as one pictograph, or that a physical keyboard
or real device works. Inspect native screenshots for tofu, isolated selectors,
broken ligatures, and clipped glyphs. Newly supported Unicode glyphs depend on
the installed OS fonts and Flutter/engine Unicode data.

Record emulator/device model, OS version, Flutter version, package ID, tested
samples/themes, screenshots, log checks, and manual keyboard/copy-paste results.
If no real Android/iOS device was used, report **尚未真机验证** for that platform.

The 2026-10-08 Android 9 emulator batch and its exact proof limits are recorded in
`docs/unicode/native-evidence/README.md`. Android physical devices and iOS remain
**尚未真机验证**; the Android sequence checks are not a claim of universal glyph coverage.
