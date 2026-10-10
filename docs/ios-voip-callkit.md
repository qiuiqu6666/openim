# iOS PushKit and CallKit

## Client ownership

Runner constructs one `PKPushRegistry` and one `CXProvider` at launch, before
Flutter is ready. PushKit tokens are independent of ordinary message APNs.
Every VoIP delivery immediately reports a native incoming call and completes
the PushKit callback after reporting. Invalid, expired, ended or wrong-account
pushes are reported and then ended without entering RTC. Duplicate pushes do
not create another SDK call.

`AppController` owns `ios_voip_callkit`; authenticated SDK accounts bind their
native session. Business events carry exact account, credential-derived
in-memory session key and room identity. Native stores only the last authorized
account ID for identifying cold incoming calls, without credentials or session
keys. Logout clears that account, calls, actions, events and subscriptions.
Old account/key callbacks cannot control a new call. Login preparation can
preserve a cold native call for the same authenticated account.

Existing `InvitationInfo.roomID` is the call identity and custom signaling
200–204 remains the business protocol. `SingleCallOwner` owns one cancellable
session; `SingleCallMedia` owns one LiveKit room for both UI and native actions.
System calls can connect/end without a mounted Flutter view; foreground UI
later borrows the active room.

System answer checks a live SDK invitation, permissions, current account and
RTC credentials, then joins RTC. Only after transport success does Dart fulfill
the real `CXAnswerCallAction`. CallKit then activates `AVAudioSession`; the
matching room opens manual WebRTC audio and publishes tracks. Waiting for audio
before fulfilling answer would deadlock. Failures terminate the call using
existing signaling and call record behavior.

CallKit owns activation; native never calls `setActive(true)`. LiveKit automatic
audio configuration is disabled during the system call. System mute controls
the shared microphone; app mute requests a CallKit transaction. Speaker controls
use native output routing without activating audio. Deactivation stops WebRTC
audio immediately; reactivation resumes only a prepared, still-current room.
Ending quarantines audio, releases tracks/RTC and then restores global settings.
Outgoing connected timing starts after the real peer joins and media is ready.

## Current server limit

The current server has no independent VoIP token binding, VoIP sending or
authoritative live invitation state. `/me/voip-push-token` and
`/calls/livekit/status/{callId}` return 404 and are not called. PushKit tokens
are never uploaded to `/third/set_push_token`: that endpoint stores ordinary
APNs and sends alert notifications. RTC credentials and completed call history
cannot prove an invitation is still ringing. Invites use `isOnlineOnly: true`.

Online SDK calls can use CallKit, and the native PushKit receiver is installed.
Terminated/offline incoming delivery still requires backend work. A push alone
does not authorize RTC acceptance; the client waits briefly for the matching
live SDK invitation and fails the system answer if none arrives. It never
replaces missing original invite time with receipt time or replays completed
call records.

To finish offline calling, add separate device/VoIP token binding and removal,
APNs `voip` sending with the signed bundle's `.voip` topic, and participant-
authorized call state synchronized with invite/accept/reject/cancel/hangup.
Return original deadlines and answered/cancelled/ended state. Cold recovery
should use that real contract after it exists.

The canonical invitation prepared by the client is:

```json
{
  "recipientUserID": "<receiving OpenIM userID>",
  "callerName": "<display name>",
  "invitation": {
    "roomID": "<original call UUID>",
    "inviterUserID": "<caller OpenIM userID>",
    "inviteeUserIDList": ["<receiving OpenIM userID>"],
    "mediaType": "audio",
    "sessionType": 1,
    "initiateTime": 1700000000000,
    "timeout": 30
  }
}
```

`initiateTime` is original Unix milliseconds (SDK seconds are normalized);
`timeout` is 1–120 seconds. This is a prospective push payload contract, not a
claim that the current server sends it. Cold acceptance still requires state
verification.

## Native bridge and verification

`ios_voip_callkit` supports install, session binding/pause, handler readiness,
event draining, token/state reads, incoming/outgoing reporting, answer/mute
transactions, action completion, connected status, speaker routing, audio gating,
end and explicit audio release. Business operations carry `sessionKey` and
`roomID`; completion carries real `actionID`. Token metadata includes
`voipToken`, `bundleId`, `apsEnvironment`, `voipTopic`; no token is persisted or
logged. Action/ringing/connection deadlines remain active without Flutter.
Info includes `voip`, `audio` and `remote-notification`; existing APNs signing
entitlement remains necessary.

Flutter tests cover headless connection order, failures/cancellation, media
cleanup, account changes, action deduplication, audio gating, mute/speaker and
ordinary APNs. Windows cannot compile/sign Runner or verify actual delivery.

On macOS, install pods and build the signed iPhone target. Verify foreground
and locked-background online calls; answer/reject/hangup from both surfaces;
permission denial; Bluetooth/speaker routing; audio interruption; logout/account
switch during connection; duplicate/expired/wrong-account pushes; delayed SDK
startup. Verify killed/offline calls after backend VoIP/state deployment using
the signed APNs environment and `.voip` topic.

Apple references: [VoIP push handling](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit),
[CallKit audio activation](https://developer.apple.com/documentation/callkit/cxproviderdelegate/provider(_:didactivate:)),
and [Introducing CallKit](https://developer.apple.com/videos/play/wwdc2016/230/).
