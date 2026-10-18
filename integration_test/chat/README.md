# Call timeline regression

`call_order_device_test.dart` uses the production chat controller, message-window
ingress and bubble widgets with simulated SDK callbacks. It checks two completed
local call records before and after three incoming picture messages. A loopback
HTTP server serves the bundled logo; no external sender or logged-in account is
required. The driver saves before/after screenshots and the asserted message IDs.

Run on a disposable test emulator. Flutter drive normally uninstalls the app at
the end, deleting its local data. Always include `--keep-app-running`, and back up
any valued device data before installing a test entry point into this package.
Restore the normal application APK afterward with `adb install -r`.

```powershell
$env:CALL_ORDER_OUTPUT = 'E:/openim/outputs/call-order-device'
flutter drive --keep-app-running --driver=integration_test/chat/call_order_driver.dart --target=integration_test/chat/call_order_device_test.dart -d emulator-5554 --no-pub
```

This proves the client receive/render path on Android, not delivery from a remote
sender through the server. Host regression tests additionally cover pending and
failed sends, replay, non-window delivery, and backwards server timestamps in
`test/pages/chat/history/chat_local_call_order_test.dart`.
