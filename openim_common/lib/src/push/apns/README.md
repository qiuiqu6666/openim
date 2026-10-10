# Apple APNs

iOS uses Apple's native remote notification registration and the existing OpenIM
device push-slot API. There is no Getui or FCM token registration on iOS.

- `apns_push_service.dart`: session ownership, serial upload/unbind, bounded retry,
  foreground renewal and native method channel events.
- `apns_push_runtime.dart`: existing account/device stores and authenticated HTTP.
- Native bridge: `ios/Runner/Notifications/APNSPushBridge.swift` in the app repo.
- Entry: existing `PushController.login`; logout runs before native SDK logout.

The server accepts `provider: apns`, `platformID: 1`, `deviceID`, raw hexadecimal
`token` and `environment: development|production`. It stores the environment with
each token and sends directly to Apple's matching endpoint. APNs credentials and
certificate passwords belong only on the server.

Bundle ID: `vip.99chat.ios`; notification extension:
`vip.99chat.ios.NotificationService`. Configure the real Apple team and provisioning
profiles in Xcode. `APNS_ENVIRONMENT` must match the signed aps-environment:
Debug uses development; Release/Profile use production unless explicitly overridden.

This module handles ordinary alert notifications. Tapping a remote notification
opens the app through iOS. PushKit/VoIP and deep links to specific conversations
are outside this module. Unit tests cover session switches, late native callbacks,
permission denial, foreground renewal, and logout during a pending upload.
