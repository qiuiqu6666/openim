# Moments UI test host

`moments_ui_fixture.dart` supplies test-only users, dynamic posts, package photo
bytes and an offline API. The production `MomentsRepository` still owns entity
versions, relationship filtering, pagination and mutations. Unimplemented API
operations cannot reach a server. The fixture never stores a token or writes to
the production privacy store.

`moments_ui_host.dart` mounts the real feed, personal album or detail route with
the application's inherited theme, translations and safe area. Its optional
author/post, locale, viewport, device pixel ratio, text scale and reduced motion inputs also support
friend albums and accessibility checks.

- `prepareMomentsUiPhotos` loads and decodes existing package assets outside
  widget-test fake time and registers cache cleanup, including failure paths.
- `mountMomentsUi(settle: false)` keeps the first frame available for gated API
  tests. Do not call `pumpAndSettle` while a test deliberately holds a request.
- `settleVisibleMomentsUiMedia` waits for native image descriptors and actual
  resized image providers. Preview exports assert that every visible image has
  decoded pixels; `pumpAndSettle` alone can finish before native codec work.
- Feed, album, detail, comments, settings, notifications, capabilities and media work can each be gated or failed
  through the fake API callbacks. Mutation records retain the target, payload
  and client request ID for behavior assertions.

The separate screenshot suite uses Microsoft YaHei on Windows and exports the
actual widget tree at 375 × 812 logical pixels with device pixel ratio 2, rendered
to 750 × 1624 PNGs. In PowerShell:

```powershell
$env:EXPORT_MOMENTS_UI_PREVIEW = '1'
flutter test --no-pub test/pages/moments/moments_ui_preview_test.dart
```

Outputs are `docs/previews/moments-99chat-{feed,profile,detail,friend-profile}-{light,dark}.png`.
The export suite is skipped during a normal test run. It captures completed
pages; loading, privacy and mutation behavior belong in the separate regressions.

`presentation/moments_page_lifecycle_test.dart` covers independent header work,
first-load range metadata, unchanged navigation returns, continuation refresh,
detail refresh continuity and failures, and reference-counted detail leases.
The layout suite also checks reduced-motion overscroll and wide-screen CTA
alignment without changing the retained like and comment buttons.

The sample owner has two posts on 3 October and one on 2 October. The feed friend
has three media items, two known actors and a known-friend reply. Empty avatar
URLs deliberately use the existing production avatar fallback; no remote avatar
requests or screenshot-only widgets are involved.
