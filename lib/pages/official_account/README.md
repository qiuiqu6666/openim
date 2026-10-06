# Official notification conversations

`99Message` and `99Pay` are read-only OpenIM single conversations. Their identity
comes from the SDK user `ex` JSON (`accountType: official`, `officialRole:
message/pay`); the two reserved IDs also resolve while offline or before profile
metadata arrives. Known IDs take precedence over inconsistent metadata.

The page uses the existing `ChatLogic`, `ChatMessageList`, SDK history/live
subscriptions, pagination, unread state and account/session guards. It does not
create HTTP endpoints, generate a welcome message, infer transaction cards from
plain text, or maintain a second message store. Text `contentType: 101` displays
the actual SDK body, including welcome and payment notifications.

## 99chat reference

The UI follows local `reference-99chat` revision `d7c3c65`:

- `lib/src/chat.dart`: official-account restrictions and the 46dp bottom spacer.
- `lib/src/widgets/chat_host_app_bar.dart`, `chat_header_title.dart`,
  `official_account_name_label.dart`, and `app_back_button.dart`: the 56dp header,
  40dp circular avatar, verified badge, name, optional online subtitle and arrow.
- UIKit `tui_chat_global_model.dart`: first visible message, local-day changes,
  or more than 300 seconds between adjacent messages produce a date divider.

Per the current product requirement, official text uses the same `ChatMessageTile`
and default `ChatItemView`/`ChatBubble` rendering as ordinary conversations. It
has no account-specific bubble style, so corners, padding, text, timestamps,
avatar geometry and light/dark colors follow the shared chat components. The
official header and read-only restrictions remain separate from message styling.
The verified PNG is copied unchanged from the reference; avatars come from the
SDK. Empty history is blank, as in the reference.

`widgets/official_account_name_label.dart` also supplies the verified name for
the address book, friend/search results, conversation/archived lists, conversation
previews and forwarding lists. List badges use the reference's 16dp size and
4dp gap; the chat header retains its 18dp badge. The label preserves SDK display
names and local remarks. Only the reserved user IDs or strict `accountType:
official` metadata earn a badge; matching nicknames and group names do not.
The reserved `assistant` user ID is also verified before SDK profile metadata
arrives. Its production AI chat title uses the same name label and 18dp header
badge; it remains an interactive assistant rather than a notification role.

## Restrictions

Header and message avatars are passive. The official identities cannot open
profile or friend/chat settings pages. Routing redirects these entries back to
the conversation. The page hides the composer, media/tools, calls, reply,
forwarding, favorites, revoke/delete and multi-selection. Copy remains available.
Sending and calling guards also enforce this when actions bypass the page.

Forward/share selectors show official notification accounts with their badge,
while selection and sending remain disabled. Contact-card sharing and group
invitation flows exclude those identities. SDK contacts remain visible in the
normal address book. Notification quick replies and stale queued reply actions
are suppressed for these accounts.

## Verification

Tests under `test/pages/official_account/` cover identity resolution, routing,
the actual SDK timeline, restrictions, theme/geometry, text scaling and safe
areas. Selection and notification regression tests cover the indirect paths.
Set `OFFICIAL_ACCOUNT_PREVIEW_DIR` when running the page tests to export actual
widget renders for visual inspection.

Verified on 2026-10-05: 85 identity/notification/timeline cases, 51 navigation,
selection, shared bubble and ordinary-contact regression cases, and 24 official
page cases passed. Sixteen actual page previews were inspected across both
themes, narrow/landscape layouts and large text. The Android debug APK build
passed. Device login and a live server notification were not exercised.

The verified-name follow-up also passed 103 relevant identity, name-layout,
directory/search, conversation/preview, forwarding-selection and official-page
cases. Four optional global-search image-export cases were skipped. The Android
debug APK was rebuilt successfully after these list changes.

The subsequent ordinary-bubble follow-up passed 24 official-page cases and four
shared bubble/footer cases, with clean focused analysis and a successful Android
debug build. Actual renders were checked for both accounts in light/dark themes,
plus enlarged text in narrow and landscape layouts. The page test synchronizes
shared `Styles` with its theme, as the application theme controller does.

Verified on 2026-10-06: the assistant badge follow-up passed 166 relevant
identity, label, address-book, assistant-page and group-selection cases; 16
optional image-export cases were skipped. Focused analysis found no issues,
light/dark assistant chat renders were inspected, and the Android debug APK
build passed. The stable assistant ID stays interactive and remains excluded
from group creation/add-member selectors.
