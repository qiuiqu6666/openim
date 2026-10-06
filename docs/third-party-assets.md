# Third-party assets

The bundled launch artwork `lib/pages/splash/assets/splash_99chat.webp` is
copied unchanged from 99chat revision `d7c3c65`, `assets/splash_new.webp`
(Apache-2.0). Android and iOS launch resources use the same artwork. Flutter
uses the reference's centered cover layout; startup authentication and routing
continue to use the existing OpenIM implementation.

The contact entry icons (`contact_new_99chat.png`,
`contact_notice_99chat.png`, `contact_groups_99chat.png`), header plus icon
(`contact_plus_99chat.png`), and navigation icons (`nav_*_99chat.png`) are from
[qiuiqu6666/99chat](https://github.com/qiuiqu6666/99chat), licensed under
[Apache License 2.0](https://github.com/qiuiqu6666/99chat/blob/main/LICENSE).

The contact-card visual tokens, curved tail and send-confirmation layout in
`openim_common/lib/src/widgets/contact_card.dart` are adapted from 99chat
revision `d7c3c65`: `lib/utils/custom_message/contact_card_message_item.dart`
and `lib/src/widgets/contact_card_send_confirm_dialog.dart` (Apache License 2.0).
The implementation uses OpenIM native card messages and the existing avatar
and message-status components.

The 2026-10-05 contact-card update moves the existing OpenIM delivery/read
component into that footer at the user's request. Its public-account display
uses the current profile API and a target-bound native card extension; the
original SDK target and invite authorization remain unchanged. This update
copies no additional artwork or reference business code.

`openim_common/assets/images/moments_cover_99chat.webp` is the default Moments
cover from 99chat's `assets/img/moments_cover.webp` (Apache License 2.0). It is
decorative cover art; published posts use authenticated backend data.

The fund assets `assets/img/red_packet_preview_cover_v2.png`,
`assets/img/red_packet_icon.png`, and `assets/img/platform_99.webp` are copied
from the local 99chat reference repository, revision `d7c3c65` (Apache-2.0).
The fund sending, password panel, message cards, opening animation and detail
layouts are adapted from its `lib/src/pages/wallet` components. OpenIM retains
its own SDK, authentication, exact decimal arithmetic and fund API contracts.
A copy of the source license is included in
[99chat-APACHE-2.0.txt](licenses/99chat-APACHE-2.0.txt).

The main-tab title decoration and fading-arc spinner, anchored quick-action
menu shape and vector icons, and `home_nav_plus_99chat.png` are adapted from
99chat revision `d7c3c65`: `lib/src/pages/home_page.dart`,
`lib/src/widgets/fading_arc_spinner.dart`,
`lib/src/widgets/home_quick_action_tile.dart` and `assets/home_nav_plus.png`
(Apache-2.0). The menu actions retain the current OpenIM navigation callbacks.

The support/edit header vector icons and conversation selection/action bar
are adapted from the same revision's `lib/src/customer_service_icon.dart`
and `lib/src/conversation.dart` (Apache-2.0). Editing uses the current OpenIM
read/delete actions and existing organizer API. Support uses the approved
99chat Kefu visitor service through the native customer-service module.

The native customer-service sheet, category grid and FAQ content are adapted
from the same revision's `lib/src/pages/customer_service/customer_service_sheet.dart`
and `customer_service_static_page.dart`; the public visitor protocol follows
`lib/src/api/kefu_visitor_api.dart` (Apache-2.0). The module reuses the current
app's glass surfaces, theme, action sheet, album picker and media browser. Its
session persistence is scoped to the current local account and service inbox.

The archived conversation navigation, natural-height rows, empty state,
swipe actions and editing bar are adapted from the same revision's
`ArchivedConversationPage` in `lib/src/conversation.dart` and
`third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitConversation/`
`tim_uikit_conversation_item.dart`. The archived page shares the OpenIM feed
row, editing controller and SDK actions with the main list; archive membership
continues to use the current Chat organizer API.

The conversation folder capsules, name dialog, management/picker menus and
folder swipe interaction are adapted from 99chat revision `d7c3c65`:
`lib/src/widgets/conversation_feed/conversation_folder_chip_bar.dart`,
`conversation_folder_swipe_region.dart`, `lib/src/widgets/app_dialog.dart`
and the folder interaction methods in `lib/src/conversation.dart` (Apache-2.0).
The implementation uses OpenIM SDK conversations and the existing Chat folder
and conversation-state endpoints, retaining the current account lifecycle and
version/conflict handling.

The message long-press action grid, dark panel and rounded outline icons are
adapted from 99chat's `tim_uikit_mobile_telegram_message_menu.dart`,
`tim_uikit_chat_message_tooltip.dart`, and `message_action_reference_icon.dart`
under `third_party/tencent_cloud_chat_uikit/lib/ui/` (Apache-2.0). The OpenIM
implementation retains its existing message permissions and SDK callbacks,
using the common popup action model/controller with a chat-specific renderer.

The in-place message selection toolbar, circular check indicators, compact
forward/delete bar and bottom delete confirmation follow 99chat's
`lib/src/widgets/chat_host_app_bar.dart`, `radio_button.dart`,
`tim_uikit_chat_history_message_list_item.dart` and `tim_uikit_multi_select_panel.dart`
(Apache-2.0). The multi-select outline icon follows `message_action_reference_icon.dart`.
The right header has an empty balance slot. Message state, local deletion, delivery
receipts and forwarding remain owned by the existing OpenIM modules.

The three bottom action icons under `lib/pages/chat/messages/selection/assets/`
(`forward_99chat.png`, `merge_forward_99chat.png`, `delete_99chat.png`) are copied
unchanged from the same revision's `third_party/tencent_cloud_chat_uikit/images/`
`forward.png`, `merge_forward.png` and `delete.png` (Apache-2.0).
They retain the mobile panel's 20px size, with the current app's theme and disabled
tints. Message menu vector icons remain a separate component.

The mobile long-press range-selection behavior adapts the baseline/range and
edge-scroll rules from 99chat revision `d7c3c65`'s desktop-only
`third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitChat/`
`TIMUIKItMessageList/desktop_message_drag_select.dart` (Apache-2.0).
The implementation uses per-chat OpenIM selection state and lazy row geometry,
supports the current reversed/centered viewport, and positions check indicators
from same-frame content anchors rather than timeline-row height.

The conversation long-press preview layout, title pill, independent action menu,
fade transition and platform backdrop behavior are adapted from 99chat revision
`d7c3c65`: `lib/src/widgets/conversation_peek/conversation_peek_overlay.dart`,
`conversation_peek_actions.dart`, `conversation_peek_message_item.dart`, and the
main/archive wiring in `lib/src/conversation.dart` (Apache-2.0). History uses the
existing OpenIM SDK/cache and shared chat renderers; previewing does not report
read receipts or clear unread counts. Tencent-specific data and controllers are
not copied into this implementation.

The group live banner, authorization/appointment/push/tip surfaces, Sangong
native operator controls/status/rules/member/agent pages, and Mark Six lottery
drawer/history/prediction/statistics/declaration/agent pages are adapted from
99chat revision `d7c3c65` (Apache-2.0), under `lib/src/widgets/group_live/`,
`lib/src/widgets/group_game_*`, `lib/src/pages/group_game/`, `lib/src/widgets/lottery_*`,
`lib/src/api/group_live_api.dart` and related native game/agent models and APIs.
They are maintained in `lib/pages/group_features/`; OpenIM authentication,
group notifications and payment inputs remain owned by the existing app.

The original live artwork is copied as `assets/img/group_live_*.webp` from
99chat `assets/live/`, with `group_live_background.webp` from `assets/livebg.webp`.
The live tutorial sheet adapts `showGroupLiveObsGuideSheet` in
`lib/src/pages/group_live/group_live_online_live_scaffold.dart`, with the unchanged
`assets/live3.webp` copied as `assets/img/group_live_guide.webp` (SHA256
`324bf4ed39bf045aa054a58a3d79e12564c29f9db59b957fbbf16db582576a0f`).
Mark Six ball artwork, latest-card watermark and
declaration icon are copied into `lib/pages/group_features/mark_six/assets/`.
The Sangong module retains its source attribution and `LICENSE-99chat`.
The full license is also available in `docs/licenses/99chat-APACHE-2.0.txt`.

The chat composer SVGs in `openim_common/assets/chat/composer/` are copied
unchanged from 99chat revision `d7c3c65`,
`third_party/tencent_cloud_chat_uikit/images/{voice,face,add,keyboard}.svg`
(Apache-2.0). Layout and theme values follow the production mobile
`TIMUIKitTextField/tim_uikit_text_field_layout/narrow.dart`,
`ui/utils/chat_input_bar_metrics.dart` and `lib/utils/theme.dart`.
OpenIM retains input controllers, drafts, mentions, SDK sends and recording.

The test-only composer reference in
`test/fixtures/chat/composer_99chat_reference.dart` independently transcribes
the same Apache-2.0 production mobile layout for rendering comparisons.

The chat microphone accessory panel and recording overlay adapt the same
99chat revision's production mobile `narrow.dart` and
`TIMUIKitTextField/tim_uikit_send_sound_message.dart` (Apache-2.0).
The original code-rendered design introduced the idle microphone and
cancel/conversion targets; no additional artwork was copied. On 2026-10-05,
the voice panel was redesigned at the user's request with a flat blue microphone,
native amplitude history, elapsed time, and labelled release targets. Tokens
and pure visuals remain under `openim_common/lib/src/res/` and
`openim_common/lib/src/widgets/chat/voice/`. The historical independent fixture
is `test/fixtures/chat/voice_panel_99chat_reference.dart`; current voice tests
validate the redesigned layout and behavior rather than historical pixel parity.
OpenIM retains its existing recorder, 60-second limit, sends and ASR review.

The chat attachment/more panel adapts 99chat revision `d7c3c65`'s production
`TIMUIKitTextField/tim_uikit_more_panel.dart`, mobile layout `narrow.dart`,
`lib/src/chat.dart` menu configuration and `lib/utils/theme.dart` (Apache-2.0).
Its original unmodified artwork is bundled in
`openim_common/assets/chat_toolbox/`: `{photo,screen,video-call,card,file}.svg`
from `third_party/tencent_cloud_chat_uikit/images/`, and
`{favorites,red_packet,transfer,group_live}.png` from `assets/chat_more/`.
Their SHA256 hashes match the reference files. Shared visuals and animation
live in `openim_common/lib/src/widgets/chat/toolbox/`; the public `ChatToolBox`
and existing OpenIM callbacks retain permissions, media selection, favorites,
contact cards, calls, funds, group capabilities, SDK sends and drafts.

The AI assistant artwork in `assets/ai/` is copied unchanged from 99chat
revision `d7c3c655b20dd06458d1882b114e68c1c24133e3`:
`{11,22,33,44,99chat}.webp`, `bg.png`, and `welcome.jpg`. All seven SHA256
hashes match the source files. The assistant layout, palette, guide, tools,
message cards, composer and search behavior adapt
`lib/src/pages/ai_assistant/ai_assistant_page.dart` and its helper modules
(Apache-2.0). OpenIM supplies actual contact/group/conversation selection,
navigation, account boundaries and attachment pickers. The user requested UI
restoration before backend integration; production AI networking is disabled
and no example replies or history are generated. Module details are maintained
in `lib/pages/ai_assistant/README.md`.

The personal contact-card friend picker under
`lib/pages/contacts/select_contacts/contact_card/` adapts 99chat revision
`d7c3c655b20dd06458d1882b114e68c1c24133e3`'s
`lib/src/pages/contact_card_user_picker_page.dart`,
`lib/src/widgets/contact_style_search_bar.dart`, `contact_list_with_presence.dart`,
`lib/src/ui/components/app_search_bar.dart`, the UIKit `directory_list_style.dart`,
`az_list_view.dart` and `avatar.dart`, and its theme tokens (Apache-2.0).
No additional artwork is copied. The picker reuses the current SearchBox,
AvatarView, PresenceLabel, GlassAppBar and AzListView; actual friends, stars,
presence, local remark/nickname/pinyin compatibility, account boundaries and
independent subscription ownership remain in the OpenIM contact modules.
Contact-card confirmation, invite/grant authorization and native SDK sends
continue through the existing application flow. Module details are maintained
in `lib/pages/contacts/select_contacts/contact_card/README.md`.

The circular favorite-picker send button adapts the visual style of 99chat
revision `d7c3c65`, `lib/src/pages/favorites/favorite_picker_sheet.dart:532–548`
(Apache-2.0): a 32dp circular surface with a 26dp Material chevron, light/dark
colors and sending progress. It reuses Flutter IconButton and the current
OpenIM favorite sending flow; no image assets or reference API code are copied.
Public FavoritePickerTokens hold its geometry/colors, with a 48dp hit area.

The friend-verification form adapts 99chat revision `d7c3c65`'s
`third_party/tencent_cloud_chat_uikit/lib/ui/views/TIMUIKitAddFriend/tim_uikit_send_application.dart`
identity/form layout and `lib/src/pages/add_friend_page.dart`'s primary action
(Apache-2.0). It reuses the current GlassAppBar, AvatarView and Flutter form
controls. No images or reference SDK/business code are copied; OpenIM retains
its grant-based friend application, group join, source fields and request limit.
Module details: `lib/pages/contacts/send_verification_application/README.md`.

The official notification conversations under `lib/pages/official_account/`
adapt 99chat revision `d7c3c65`'s `lib/src/chat.dart`, `chat_host_app_bar.dart`,
`chat_header_title.dart`, `official_account_name_label.dart`, `app_back_button.dart`,
the UIKit text/history row layout and `ui/widgets/chat_text_bubble_layout.dart`
(Apache-2.0). The verified badge
`lib/pages/official_account/assets/official_account_verified.png` is copied
unchanged from the reference's `assets/official_account_verified.png`. The
generic last-line text/footer layout is adapted into shared OpenIM widgets,
with opt-in presentation parameters; no Tencent SDK/business implementation is
copied. Official identity, receipt/history delivery and all account/session
boundaries use the existing OpenIM SDK. Module details are maintained in
`lib/pages/official_account/README.md`.

The built-in blue 99CHAT mascot sticker pack under
`lib/pages/chat/stickers/builtin/assets/4351/` is copied unchanged from
99chat revision `d7c3c655b20dd06458d1882b114e68c1c24133e3`, source directory
`assets/custom_face_resource/4351/`: `ys00@2x.png` through `ys15@2x.png` and
`menu@2x.png` (Apache-2.0). All 17 copied SHA256 hashes match the source;
their Git blob hashes also match that reference revision. Each original PNG
is 240×240 with transparency. The catalog follows the original order in
`lib/utils/constant.dart`; `lib/utils/sticker_constants.dart` identifies
4351 as the visible large-sticker pack. Catalog labels describe the artwork
for accessibility, since the reference contains file names without action
labels. The source license is retained in
[99chat-APACHE-2.0.txt](licenses/99chat-APACHE-2.0.txt). Catalog and artwork
ownership are documented in `lib/pages/chat/stickers/builtin/README.md`;
OpenIM retains its own SDK sends, account boundaries and message rendering.

The six single-call control images under `openim_common/assets/call_ui/`
are copied unchanged from 99chat revision
`d7c3c655b20dd06458d1882b114e68c1c24133e3`, source directory
`assets/call_ui/`: `mute.png`, `mute_on.png`, `handsfree.png`,
`handsfree_on.png`, `hangup.png` and `dialing.png` (Apache-2.0).
All six SHA256 hashes match the reference files. The full-screen palette
adapts the reference's `lib/src/pages/livekit_call_page.dart` solid
`#2D2D2D` call canvas and white text. The existing OpenIM layout, signaling,
LiveKit media callbacks and PiP ownership remain in their current modules.
The source license is retained in
[99chat-APACHE-2.0.txt](licenses/99chat-APACHE-2.0.txt). Visual ownership is
documented in `openim_live/lib/src/widgets/call_surface/README.md`.

The create-group default avatar
`lib/pages/contacts/create_group/assets/default_group_avatar.svg` is copied
unchanged from 99chat revision `d7c3c65`, `assets/default_group_avatar.svg`
(Apache-2.0). The form follows `lib/src/create_group.dart`'s mobile cards,
member picker entry points and terms declaration. Group creation and member
selection continue to use the existing OpenIM SDK and controller.

The conversation empty-state illustration
`lib/pages/conversation/empty/assets/99chat_empty.png` is derived from the
user-provided `ChatGPT Image 2026年9月21日 01_50_15.webp`. ImageGen removes
the white background for light and dark themes while retaining the 99CHAT
mascot, paper plane, chat bubbles, box and plant. The original input file is
preserved. This artwork is separate from the reference repository's existing
`empty.webp`; presentation ownership is documented in
`lib/pages/conversation/empty/README.md`.

The wallet journal red-packet icon
`lib/pages/wallet/record/assets/red_packet.png` is copied unchanged from the
user-provided `红包.png` on 2026-10-06. Its transparency and original pixels are
preserved. Packet journal rows use this icon for sent, received, freeze and
settlement events; the detail page retains the currency logo.

The wallet refund icon `lib/pages/wallet/record/assets/refund.png` is copied
unchanged from the user-provided `退款中.png` on 2026-10-06. Packet and withdrawal
refund events and legacy refund rows use it in the same themed circular
container. The current status of an associated order does not replace the icon
of earlier sent, frozen or settlement events.

The wallet currency icons `lib/pages/wallet/widgets/assets/trx.png` and
`lib/pages/wallet/widgets/assets/usdt.webp` are copied unchanged from the
user-provided `TRX.png` and `usdt20250820172730.png` on 2026-10-06. The latter
file contains WebP bytes despite its original .png filename, so its bundled
extension matches the actual format. Wallet coin displays retain the original
colors and transparency, clip them as circles and load them from local assets;
backend image URLs do not override these two currency marks.

The six dice animations under `openim_common/assets/chat/dice/` come from the
six animated WebP attachments provided by the user on 2026-10-06. Their
original bytes and transparency are preserved. Each is 512×512 with 181 frames
of 16 milliseconds, played once at its original speed (2896 milliseconds).
File numbers identify the settled result; the fifth and sixth attachments
settle at 6 and 5 respectively, so their bundled names match those outcomes.
The previously bundled dice Lottie JSON files have been removed.
Source names and SHA-256 hashes are retained in that asset directory's
`README.md`; message protocol and playback ownership are documented in
`lib/pages/chat/stickers/dice/README.md`.
The matching `dice_*_final.webp` files are lossless single-frame exports of the
fully composited last frames. Their RGBA pixels match the animation results.
History and thumbnails use these stills to avoid decoding 181 invisible frames
on the same engine queue as an active roll; the original animations are unchanged.

## 认证页面

`assets/img/language_switch.png` 来自本地 `reference-99chat/assets/img/language_switch.png`，用于按参考仓库还原认证页切换语言图标。认证页布局与输入框亦参考其 `lib/src/ui/auth_widgets.dart`；接口继续使用 OpenIM 协议。
