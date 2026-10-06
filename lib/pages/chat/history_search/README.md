# Conversation history search

`chat_history_search_page.dart` is the entry used by single/group chat settings.
The old `chat_setup/chat_history_search_page.dart` import remains an export for
existing callers. Global search can still supply `initialQuery` and `filesOnly`.

- The conversation search surface follows 99chat's `src/search.dart` and
  `tim_uikit_search_msg_detail.dart`: no title bar, a neutral 44px search field
  with Cancel, and persistent circular content shortcuts above results.
  Entry focuses the search field, as in the reference. Native phone row geometry
  stays stable when the keyboard reduces viewport height; wide/native-desktop
  layouts and web landscape use the reference's desktop metrics.
  Single chats show Media/File; groups also show Date/Group members. The callers
  supply the real conversation type, including the global-search entry.
- Keyword changes search in the current page after 500ms. Submission searches
  immediately, cancelling the pending timer. Blank input only shows shortcuts;
  clearing it invalidates in-flight results rather than searching all history.
  Opening a category pauses an unsent draft search and resumes it on return.
  Completed results and scroll position survive category navigation.
- `widgets/` owns search chrome, shortcuts, keyword results and result rows.
  `chat_history_search_tokens.dart` records reference geometry and colors.
  The local search field is needed because shared `SearchBox` cannot express
  99chat's 34px prefix/suffix constraints or centered 1.2-height input line.
  Existing `AvatarView`, `AppTokens`, empty-state asset and message time helper
  are reused. Search rows show sender/time first and a two-line preview second,
  with circular sender avatars, subtle inset dividers and no navigation arrow.
- `selection/` owns the date calendar and current-conversation sender selector.
  Cancellation returns to the unchanged search entry. Selecting a date or member
  opens `chat_history_results_page.dart` with that scope.
- Results reuse one page/controller for media, pictures, videos, files, voice, dates,
  senders and keywords. Original-message actions use
  `navigation/chat_history_message_navigation.dart` to confirm the exact SDK
  record, return to the active chat's concrete route, and position that message.
  Existing drafts and route-owned resources survive the return. Entry from
  another conversation uses the ordinary/official/assistant chat dispatcher with
  a `searchMessage` argument and an account/current-entry guard.
- `filtered_results/` presents member/day history as 99chat's
  `TIMUIKitConversationFilterMsgPage.byMember/byDate`: the member's name or
  localized short date is the header title, with no keyword field or separate
  scope label. Entering shows all messages in that member/day scope rather than
  inheriting the hub's keyword. Both use the same presentation and reuse the
  SDK search/controller and summary tile, with full-width row surfaces and a
  0.6px divider from the text inset to the right edge after every message.
  Chat background/header colors come from `ChatComposerTokens`; loading, empty
  and load-more geometry follow the reference. Retry uses the existing OpenIM
  controller, which does not expose Tencent's scan-pause state. The parent retains account,
  expiry and original-message navigation guards, and pull-to-refresh remains.
- `media/` presents picture/video categories as 99chat's square 3-column grid
  (4 columns from 480 logical pixels), with 2-pixel gutters and video play icons.
  Tapping ordinary media reuses `ChatPictureGallery` and `IMUtils.previewMediaFile`
  for swiping/saving; returning keeps the grid's scroll position and query.
  Private messages retain their original-message path. Animated stickers carried
  as OpenIM videos are excluded at result acceptance, while raw SDK page sizes
  and offsets remain intact so older ordinary videos can still be found.
- `files/` presents the file name and localized time without message prefixes,
  sender names or navigation arrows. It reuses `ChatFileMessageView`'s download,
  cache and system-open workflow through its presentation builder, including
  busy/retry states. The existing filename search remains available.
  File rows use the reference's dense/compact `ListTile`, 16/13 text sizes,
  16/2 content insets and full-width dividers. Page background, continuous file
  rows and search input use `AppTokens.background`, `surface` and `surfaceAlt`
  respectively; the header/search region shares the row surface, while the
  list's surrounding space retains the page background. File icons have no
  separate background block. The shared
  `formatChatMessageTime` supplies the same 24-hour rolling-week timestamps as
  conversation previews; long filenames and scaled text can increase row height.
  File search chrome, input text/icons/selection, attachment actions and loading
  states share the same neutral colors and brand accent. It explicitly resolves
  those colors from the active theme instead of mixing legacy Styles colors,
  generated Material colors and 99chat tokens on one surface.
- Media combines SDK picture/video types in one gallery. Animated stickers are
  excluded while raw paging remains intact. Existing independent picture/video
  and voice categories remain supported for direct callers.
- Media, pictures, videos and voice browse their category without a keyword field:
  OpenIM has no keyword index for their content. Member/date results browse the
  complete selected scope; files can refine results with text. The entry's draft
  remains intact when returning.
- `chat_history_search_source.dart` adapts the real OpenIM local search API and
  defines its filter value object; it has no page dependency.
- `chat_history_search_controller.dart` owns request generations, raw SDK page
  offsets, loading/retry and result state. Each results page disposes its own
  controller. No SDK event subscription or shared chat controller is replaced.
- Sender names come from the requested conversation and SDK member/user data.
  Each row shows the public user nickname when available, falling back to its
  existing member/conversation name. The original alias remains available for
  searches; group search still follows SDK member-card matching. Public profiles
  are resolved only for the valid members of the current SDK page, without
  changing raw offsets or making an optional profile failure fail the page.
  No entered ID or fabricated member list is used in production.
- The sender directory reuses the contacts name indexer and `AzListView` for
  pinyin/A–Z/# sections and the right-hand touch/drag index. The projection is
  refreshed after a source page arrives, reusing unchanged-name pinyin. Search
  resets both rows and index; pagination keeps the SDK cursor and visible sender.
  Index entries reflect the currently loaded members rather than unavailable
  letters, and loading/retry controls stay outside the indexed data.
- Sender rows reserve two lines: nickname, then the contacts `PresenceLabel`.
  Every member row has the reference's 0.6px themed divider aligned with the
  nickname, including the final member; the alphabetical index remains separate.
  The layout references 99chat's `tim_uikit_conversation_member_picker_page.dart`.
  The shared `ContactsLogic` owns the real presence cache, privacy labels and
  subscriptions. The page reports only the indexed list's visible users through
  its existing positions listener; covering/backgrounding the page or disabling
  online display pauses its owner, and disposal releases only that owner. Missing
  ordinary presence remains blank. Official service accounts resolve to online
  through the shared contacts display policy, using the existing SDK profile's
  `ex` metadata; raw presence cache and ordinary privacy remain unchanged.
  No store, HTTP client or SDK listener is created by
  this selector; cached labels require the original account/current session.
- Other category and selection routes use the existing 17sp semibold heading and
  blue back icon. Index text fits the remaining viewport on compact screens.

The native SDK does not implement `senderUserIDList` filtering. The controller
checks `sendID` and advances raw SDK pages until the visible page is filled or
history ends. Dates use local calendar boundaries and a half-open interval.
Empty-keyword category requests include valid message types required by OpenIM.
Every returned search group is limited to the requested conversation ID.
The production source pins the SDK account and token for the page's lifetime;
account changes invalidate in-flight results and further pagination.

The date selector enables only days with searchable local messages in this
conversation. `selection/date_availability/` probes the displayed month one day
at a time with a one-message SDK page and at most three concurrent requests;
it never scans the entire conversation. Unknown, empty and failed-to-load days
remain disabled. Native inclusive midnight bounds are checked against the
local half-open day, advancing past adjacent-day rows without dropping the
last milliseconds of the requested day. Changing months and returning from
the background refresh availability; confirmation rechecks the selected day
so removing its last message cannot open an empty result page. The page keeps
the existing calendar, theme, navigation and confirmation styles.

Reference behavior: 99chat's `tim_uikit_search_msg_detail.dart` opens category
pages, then date/member-specific results. The main search and persistent
shortcuts follow that implementation; legacy direct categories remain available.
Shared `GlassAppBar`, `SearchBox`, `AvatarView`,
`ChatVideoThumbnail`, theme values and `AppTokens` supply presentation. Voice
results share the file page's continuous surfaces, compact geometry and fine
dividers. The blue microphone, localized voice label and valid SDK duration
form the main line; trimmed sender names and `formatChatMessageTime` form muted
metadata, stacked for larger text. Missing durations are not fabricated. Rows
open the original message and do not download audio or initialize playback.
Private rows reuse `ChatExpiringContent` to hide content when its read deadline
passes, and the tap handler rechecks expiration before navigating to the message.
Media cells use its optional builder to keep the notice inside the square;
expired children are never mounted. Private media is excluded from ordinary
galleries. Page/attachment actions also check the captured account and token.

Media/file presentation references 99chat's
`tim_uikit_conversation_media_file_page.dart`. The media shortcut opens a combined
picture/video grid; files retain the existing scoped file browser and actions.

Tests live in `test/pages/chat/history_search/`: SDK parameter/state contracts,
sender/date selectors, group/single shortcuts, inline keyword search, clear and
request cancellation, results/retry/back behavior, large text and private expiry.

2026-10-05 date-result alignment: 168 history-search tests passed, including nine
new date-page regressions and the existing member-result tests. Ten opt-in preview
jobs were skipped because their output directories were unset; three dedicated
date previews were rendered and inspected separately (light, dark and 320px at
200% text). Module/test static analysis reported no issues and the Android debug
APK built successfully. Physical-device and native iOS builds were not checked.
The new `date_results/` tests cover localized titles, local-day boundaries,
keyword-free scope, pagination/retry, main-search draft restoration and expiry.

2026-10-05 original-message navigation: search results return to the actual chat
and focus the message; user edge dragging automatically pages both directions.
The complete related regression passed 486 tests with ten opt-in preview jobs
skipped. Static checks found no errors/warnings (existing info diagnostics remain),
and the Android debug APK built successfully. Route identity, account, cached
startup, late window results, drafts, expiry and live-buffer verification are
recorded in [the validation report](../../../../docs/chat-search-jump-pagination-validation.md).
