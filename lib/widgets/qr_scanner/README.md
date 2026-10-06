# Shared QR scanner

`QrScannerPage<T>` owns the existing full-screen camera, scanning frame, flash,
gallery selection and optional personal-QR action. Its visual layout and drawing
come from the existing 99chat-aligned friend scanner, using public
`QrScannerTokens` and `AppTokens`. Both themes keep the same dark camera surface.

- `qr_scanner_page.dart`: the generic Stateful page and camera lifecycle.
- `qr_scanner_layout.dart`: immutable header, instruction viewport, native scan
  window and control geometry. Portrait crowding uses a scrollable instruction
  viewport, a horizontal flash action and smaller decorative gaps/padding while
  retaining system text size and at least 48dp controls.
- `qr_scanner_overlay.dart`: mask, scan animation and controls; exports the layout
  to retain existing imports.
- `qr_gallery_service.dart`: existing `image_picker` selection and `compute`
  image decoding/ZXing recognition. It returns raw text without parsing business
  data; bounded image sizes, orientation, polarity and UTF-8 handling are retained.
- `qr_scanner_labels.dart`: simplified/traditional Chinese, English, Japanese
  and Korean labels. Chinese script/region selection matches the app language
  convention; unsupported languages use English.

```dart
QrScannerPage<MyResult>(
  parseCode: parseMyQrPayload, // Non-throwing: return null for unsupported input.
  keyPrefix: 'my-qr',
  invalidCodeMessage: (context) => localizedInvalidMessage(context),
)
```

The page returns a successful `T` via `Navigator.pop<T>` exactly once.
`parseCode` accepts trimmed camera/gallery text and is supplied by the business
module. The default `keyPrefix` is `qr`; control keys are `$keyPrefix-back`,
`-album`, `-flash`, `-my-code`, `-title`, `-instruction` and `-frame`.
`-instruction` identifies the actual visible viewport, including when the full
text scrolls inside it. `onMyQrTap` is optional: when absent,
its control is hidden. `QrGalleryService` is injectable for tests.

Camera commands remain serialized and read the latest desired activity state.
Covered routes, backgrounding, gallery work and personal-QR navigation pause
scanning. Native gallery callbacks wait until the page is foregrounded before
decoding or returning results; closing the page releases that wait. Disposed or
obsolete controllers and late results cannot navigate. `QRView` owns native
controller disposal; the page owns subscriptions, timeout and animation only.
Reduced motion stops the scan animation, and layout follows safe-area padding,
landscape and scaled text.
The toolbar measures translated title and album text at the current system
scale. If the centered title conflicts with an action, it moves to a full second
row; effective header height and the instruction/native scan window follow that
change. Normal-size positions retain the reference layout.

The shared directory imports only Flutter, public `openim_common` and existing
scanner/image packages. It does not import contacts, wallet or their parsers.
Friend entry paths retain wrappers under `pages/contacts/scanning/`, including
the original gallery alias and overlay exports. Existing friend scanner tests
exercise the shared lifecycle and recognition; native device camera/album
permissions still need device validation.
