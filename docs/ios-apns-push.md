# iOS direct APNs

The iOS Runner uses direct APNs for offline message notifications. The native
bridge only obtains a device token and delivers notification taps. The Flutter
push service owns the authenticated OpenIM token binding and chat navigation.
The separate [PushKit / CallKit module](ios-voip-callkit.md) owns calling.

## OpenIM API and Flutter ownership

`AppController` owns `APNsPushRuntime` in `lib/core/push/apns/`. It starts only
on iOS once the Chat login, OpenIM SDK session, and home route are ready. A fresh
authentication grant survives splash/login navigation. Repeated ready callbacks
share initialization and do not repeat an acknowledged token binding.

The backend contract uses `Config.imApiUrl` with its full configured prefix,
`token: <imToken>`, `operationID`, and JSON bodies. It does not use the Chat token,
`X-Tenant-Id`, or `updateFcmToken` for APNs.

```http
POST /third/set_push_token
{
  "platformID": 1,
  "deviceID": "<stable login device ID>",
  "provider": "apns",
  "token": "<hex APNs token>",
  "environment": "development"
}
```

A successful registration requires a 2xx status, integer `errCode: 0`, and
matching `data.userID`, integer `data.platformID: 1`, and `data.deviceID`.
Logout sends `POST /third/delete_push_token` with
`{"platformID":1,"deviceID":"<same ID>"}` using the captured old IM identity.
Its receipt must match the user/platform and contain nonnegative integer
`data.removed`. Empty HTTP 204 is not a confirmation. Uploads and deletions share a queue so a
late old-account upload cannot follow its deletion. Native callbacks, queued
uploads, and tap actions lose ownership immediately on logout/account change.
Only a validated deletion receipt marks cleanup as successful. Failed logout
cleanup retains its captured old IM identity and device scope in memory, with
a cooldown before later session-ready, foreground or explicit logout retries.
Cleanup and new registrations remain serialized. Starting a new registration
for the same account/device supersedes that scope's old cleanup retry so a late
retry cannot delete the new binding; other accounts' failed cleanup stays pending.
These retries do not survive process termination, and a revoked old IM token
cannot authorize deletion. Server-side logout revocation or conditional cleanup
is needed to guarantee removal in those cases; failure is never reported as a
confirmed unbinding.

Token refreshes rebind the device. Failed permission/registration/binding is
retried on a later session-ready or foreground callback after a 30-second
cooldown; failures do not block login. A native registration failure invalidates
in-flight registration/cache results, so they cannot upload an older cached token
or clear the failure's cooldown. Tokens are kept in memory, without logging.

### Notification tap payload

The current backend emits the recipient and message ID alongside an `ex` JSON
string. All ordinary client sends use one shared offline push factory, with
`isOnlineOnly: false`, title `99CHAT`, generic description, default sound and
iOS badge enabled. The route describes the destination conversation type,
including for forwards; it is not taken from the forwarded source message.

```json
{
  "aps": {"alert": {"title": "99CHAT", "body": "你收到了一条新消息"}, "sound": "default", "badge": 3},
  "openimAPNS": true,
  "accountID": "<receiving OpenIM userID>",
  "clientMsgID": "<message ID>",
  "ex": "{\"version\":1,\"type\":\"chat_message\",\"sessionType\":3,\"sendID\":\"<sender>\",\"groupID\":\"@example\"}"
}
```

The server fills `accountID` and `clientMsgID`; the sender fills `ex` with integer
`version:1`, `type:"chat_message"`, the actual SDK `sessionType`, `sendID`, and
`groupID` (empty for private chat). Private taps locate the sender; group taps
locate `groupID`. The receiver verifies the recipient, parses `ex`, waits for SDK
login/message synchronization and retrieves the actual SDK conversation. It
then creates the current local session target and reuses notification actions
and chat navigation. Clicks deduplicate by recipient plus message ID. No message
content is synthesized from the alert, and no extra SDK login is created.

Old canonical conversation/source payloads remain accepted with identity checks.
Missing/invalid `ex` without that legacy route or an unavailable SDK conversation
returns to the normal message tab for the verified current account. Mismatched
accounts are ignored. When a send cannot
retrieve the destination group's actual type, it still sends the generic alert
without a route rather than guessing another conversation.

Actual foreground transitions renew the same token binding; routine route-ready
callbacks do not repeatedly upload it. A binding older than a day is also renewed
when the SDK session becomes ready, before the server's 30-day expiration.
Disabling this account's “notify when closed” choice removes only this device's
ordinary APNs binding, while clicks on notifications already delivered remain
available. Enabling it registers and binds again. Existing server global/conversation receive options continue
to control do-not-disturb. Local content-preview/sound choices have no confirmed
server synchronization contract; offline alerts retain generic text/default
sound. PushKit calling remains independent of the message notification switch.

## Native channel

Channel: `ios_apns_push`, implemented in
`ios/Runner/Notifications/IOSAPNsPushBridge.swift`.

| Dart method | Arguments | Result |
| --- | --- | --- |
| `install` | None | `null`; idempotent, without a permission prompt |
| `setNotificationTapHandlerReady` | `{"ready": true}` or `{"ready": false}` | `null` |
| `activateNotificationTaps` | None | `null`; restores authenticated click delivery without requesting permission or registering a token |
| `registerForRemoteNotifications` | None | `{"authorizationStatus": "authorized"}`; other values are `denied`, `provisional`, `ephemeral`, `notDetermined` |
| `getCachedTokens` | None | `{"apnsToken": "<hex>", "bundleId": "<bundle>", "apsEnvironment": "development"}`; token/environment can be empty |
| `consumePendingNotificationTap` | None | The pending payload map, or `null`; consuming clears it |
| `unregisterForRemoteNotifications` | None | `null`; unregisters and clears token, pending tap, and handler readiness |

| Native event | Arguments |
| --- | --- |
| `onApnsToken` | The complete `apnsToken` / `bundleId` / `apsEnvironment` map |
| `onNotificationTap` | Original remote payload with codec-safe string keys and nested data preserved |
| `onRegistrationError` | `{"domain": "<NSError domain>", "code": 123}`; no token or error detail |

The Flutter service installs its method handler before marking the tap handler
ready, then consumes any pending tap. Every new authenticated session activates
tap delivery independently of the offline-notification switch. Registration success is asynchronous: a
permission result does not mean a device token has been obtained or bound on the
server. Tokens are held only in native memory and are never printed.

Actual remote notification responses are cached before Flutter is ready. The
bridge does not interpret a background launch payload as a user tap. It forwards
only the default action on `UNPushNotificationTrigger`; local notification
responses remain with `FlutterAppDelegate` and `flutter_local_notifications`.
Remote foreground notifications are silent because the existing OpenIM message
runtime owns foreground notification presentation.

Logout disables token registration and tap delivery, clears all bridge state, and
invalidates an in-flight permission request. A late registration callback cannot
re-enable a logged-out bridge. The next login reactivates clicks and registers
again when offline notifications are enabled. Cold-start SDK login preparation
preserves the cached user tap; explicit logout clears it even before native
registration has started. A first cold SDK login preparation without an existing
Flutter push owner does not issue an orphan-token deletion or wait on that network
request; the authenticated session registers or applies its preference afterwards.

## Build and signing

Runner has Push Notifications and Background Modes capabilities, and
`remote-notification` is present in `UIBackgroundModes` alongside existing audio.
`APNS_ENVIRONMENT` is `development` for Debug and `production` for Profile/Release.
Both `Runner.entitlements` and the `APNsEnvironment` Info.plist value use this
setting. A device's embedded provisioning profile takes precedence when it
exposes `aps-environment`; the declared build value supplies the App Store fallback.
The signing profile must grant the same entitlement for the unchanged Runner
bundle ID, and the server's APNs topic/environment must match the signed app.
The client does not install or select an Apple signing profile or server key.

Firebase Messaging automatic initialization/delegate proxy are disabled in the
iOS Info.plist, and Runner no longer initializes Firebase. Its Dart/Android
dependency remains. The iOS Firebase Messaging plugin registers APNs even without
a configured Firebase app, so `ios/scripts/apns_only_plugins.rb` removes only its
registration line from the generated iOS registrant. Both `Podfile` post-install
and the Runner build phase run this idempotent filter. The build phase runs after
Flutter's script and before compiling Sources, so Flutter regeneration cannot
silently restore a second notification owner. Other plugin registrations remain.

The existing NotificationService extension is not required for plain alert APNs
and is not enabled by this change. Rich notification/avatar extension work is
outside this message-token integration.

## Validation

Windows validation on 2026-10-11 passed 776 tests covering APNs token binding,
native channels, remote clicks, sending/forwarding, account/session cleanup,
home navigation and system calling. The final multi-account cleanup adjustment
also passed 146 focused APNs/session lifecycle tests. Static analysis of the new
module and changed application/test files is checked separately from unchanged
legacy package lints. The Android debug APK build passed.
The unchanged legacy Firebase section of `push_controller.dart` still has its
existing informational naming/print lints. Ruby and Swift are not installed on
this host; the native filter tests and iOS build have not been executed here.

Run `ruby ios/scripts/test/apns_only_plugins_test.rb` for the real registrar
filter: preservation of local notifications/IM plugins, CRLF, repeated filtering,
Flutter regeneration, and rejection of an unexpected Firebase registration form.
Flutter channel/service tests cover the Dart side of the contract. Native Swift
compilation, entitlements after signing, and actual APNs delivery need macOS/Xcode
and a signed device build; a Windows source check cannot establish those results.

On a signed iPhone, verify:

1. A clean login requests notification permission once. Allowed/provisional
   results produce one hexadecimal APNs token binding; denied permission does not
   bind an empty token.
2. A token callback during logout does not upload or recreate state. A subsequent
   login registers and binds the device to the current account.
3. A background APNs alert displays once. Tapping it opens its chat after session
   readiness. A terminated-app tap is consumed once after Flutter installation.
4. A remote foreground notification creates no extra native banner/sound. Existing
   SDK-generated local notification display and local notification taps still work.
5. A silent/background launch does not navigate to a conversation merely because
   its payload exists. Check sandbox/production delivery with the final signed
   `aps-environment`, rather than inferring it from Debug/Release alone.
6. Disabling offline notifications removes this device's binding while old
   notification taps still work. Re-enable, foreground renewal, device-token
   rotation, and logout/account switching use the correct captured IM identity.
7. Private and group sends, replies, forwards, shared contacts and shared app
   messages all carry the destination's SDK type. Old/no-route notifications and
   missing SDK conversations return to the message tab; stale accounts never open.

Apple references: [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
and [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server).
