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

CallKit supplies incoming ringing, but the app plays the outgoing waiting tone
using the existing `CallRingtone` player and bundled ringback asset. For system
calls, credential completion does not start the player: `SingleCallOwner` first
waits for native audio activation and media publication, then emits
`onWaitingAccept`. The player receives `systemAudio: true` and does not activate
or reconfigure `AVAudioSession`. Acceptance, rejection, cancellation, timeout,
logout and disposal retain the existing stop and stale-callback guards.

The 2026-10-11 regression reproduced silent outgoing calls with a system adapter:
the old controller rejected every tone whenever CallKit was present. Coverage
now distinguishes incoming system ringing from app-owned outgoing ringback,
checks the activation boundary and terminal callbacks, and preserves the
existing non-system calling path. Device audibility, silent-switch behavior,
receiver/speaker/Bluetooth routing and iOS builds still require an iPhone/macOS.
Validation: all 241 tests in `test/pages/chat/calling` and
`test/core/calling/ios` passed. Targeted analysis reported no errors or warnings;
the controller retains six pre-existing brace-style information messages.

## Offline calling contract

The separate `calling-api` service owns `/calling/*` on the Chat API HTTPS host.
Every request uses the existing **Chat token** in `token` and a unique
`operationID`. It does not use the reference app's `/me/voip-push-token` or
`/calls/livekit/*` paths. Ordinary APNs remains on `/third/set_push_token`.

| Method | Path | Body / purpose |
| --- | --- | --- |
| POST | `/calling/voip/register` | `deviceID`, hexadecimal `token`, `bundleID`, `environment` (`production` / `development`) |
| POST | `/calling/voip/unregister` | `deviceID`; removal is scoped to the authenticated account and session |
| POST | `/calling/invite` | `deviceID`, original `invitation`; validates caller, friendship and blocks, persists state and queues VoIP |
| POST | `/calling/status` | `callID`; only the two participants may read state |
| POST | `/calling/action` | `callID`, `deviceID`, `action` (`accept`, `reject`, `cancel`, `hangup`), original `invitation` for cancellation races |

Responses use `{ "errCode": 0, "data": ... }`. Call data contains `state`,
`recipientUserID`, server-resolved `callerName` / `calleeName`, `invitation`,
`expiresAt`, `updatedAt` and `answeredDeviceID` after acceptance. States are
`ringing`, `accepted`, `rejected`, `cancelled`, `ended`, `expired`.
HTTP 200 alone is not success. A competing answer/terminal-state conflict uses
`errCode: 409`; a missing legacy call uses `errCode: 404`.

The existing OpenIM 200–204 signals and RTC room are retained. Updated Android
and iOS callers persist transitions before sending their SDK signals. Active Android and iOS calls renew the server
lease every 10 seconds; a 45-second lease releases abandoned calls after both
processes disappear. A
cancel-before-invite tombstone prevents late HTTP completion resurrecting a call.
An old caller can still make an online SDK call, but cannot start offline VoIP:
both sides must use the updated app for the complete offline flow.

On iOS, native PushKit reports CallKit immediately with the pushed nickname.
After authenticated SDK startup, `IOSVoIPBackend` queries server state and
restores only a matching, unexpired, ringing invitation. Push JSON alone never
authorizes answering. The existing media owner handles permissions, RTC joining,
CallKit audio and signaling. Status polling closes cancelled/expired/answered-
elsewhere system surfaces. Profile lookup updates the system name asynchronously;
the placeholder is `99chat`, not an internal IM ID.

Token binding is serialized against logout, tied to installation/account/session,
and separate from ordinary APNs. The backend rechecks token revocation before
sending, uses the actual signing environment, and never sends VoIP pushes to
cancel calls. APNs uses the `.voip` topic, push type `voip`, priority 10 and
expiration 0. The Redis outbox retries transient failures within the original
ringing deadline and deduplicates successful device deliveries.

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
`timeout` is 1–120 seconds. This is the server push payload contract. Cold acceptance still requires
participant-authorized state verification.

## Native bridge and verification

`ios_voip_callkit` supports install, session binding/pause, handler readiness,
event draining, token/state reads, incoming/outgoing reporting, answer/mute
transactions, action completion, connected status, speaker routing, audio gating,
end and explicit audio release. Business operations carry `sessionKey` and
`roomID`; completion carries real `actionID`. Token metadata includes
`voipToken`, `bundleId`, `apsEnvironment`, `voipTopic`; the native token is kept
in memory and bound to the backend, and is never logged. Action/ringing/connection deadlines remain active without Flutter.
Info includes `voip`, `audio` and `remote-notification`; existing APNs signing
entitlement remains necessary.

Flutter tests cover headless connection order, failures/cancellation, media
cleanup, account changes, action deduplication, audio gating, mute/speaker and
ordinary APNs. Linux cannot compile/sign Runner or verify actual iPhone delivery.

On macOS, install pods and build the signed iPhone target. Verify foreground
and locked-background online calls; answer/reject/hangup from both surfaces;
permission denial; Bluetooth/speaker routing; audio interruption; logout/account
switch during connection; duplicate/expired/wrong-account pushes; delayed SDK
startup. Verify killed/offline calls with the newly signed app and deployed service using
the matching APNs environment and `.voip` topic. A previously installed app must
log in once after upgrade to register its independent PushKit token. TestFlight
uses production; a development-signed build needs the development environment.
Actual delivery and launch remain subject to iOS, network and device conditions;
server acceptance is not proof of a displayed or answered call.

Apple references: [VoIP push handling](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit),
[CallKit audio activation](https://developer.apple.com/documentation/callkit/cxproviderdelegate/provider(_:didactivate:)),
and [Introducing CallKit](https://developer.apple.com/videos/play/wwdc2016/230/).
