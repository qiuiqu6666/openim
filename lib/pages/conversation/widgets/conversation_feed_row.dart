import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

import '../conversation_logic.dart';
import '../editing/conversation_selection_indicator.dart';
import '../summary/conversation_latest_message_text.dart';
import '../../official_account/widgets/official_account_name_label.dart';
import 'conversation_feed_style.dart';
import '../../group_features/widgets/group_live_avatar.dart';

/// Shared conversation presentation for the main feed and archived feed.
///
/// The caller owns gestures, editing state and the sliding action controller.
/// Keeping this Material inside the caller's sliding transform prevents ink
/// decorations from retaining their offset when a swipe closes.
class ConversationFeedRow extends StatelessWidget {
  const ConversationFeedRow({
    super.key,
    required this.logic,
    required this.info,
    required this.showDivider,
    required this.editing,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.archivedLayout = false,
  });

  final ConversationLogic logic;
  final ConversationInfo info;
  final bool showDivider;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool archivedLayout;

  double _spacing(double value) => archivedLayout ? value : value.w;

  bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Color _background(BuildContext context) {
    if (!archivedLayout) {
      return ConversationFeedStyle.rowBackground(context,
          pinned: info.isPinned == true);
    }
    return info.isPinned == true
        ? AppTokens.surfaceAlt(dark: _dark(context))
        : AppTokens.surface(dark: _dark(context));
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _background(context),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: archivedLayout
              ? _buildArchivedLayout(context)
              : Stack(
                  children: [
                    SizedBox(
                      height: ConversationFeedStyle.rowHeight(context),
                      child: Padding(
                        padding:
                            EdgeInsets.fromLTRB(editing ? 12 : 16, 8, 16, 0),
                        child: _buildContents(context),
                      ),
                    ),
                    if (showDivider)
                      Positioned(
                        left: editing ? 118 : 82,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: ConversationFeedStyle.dividerHeight,
                          color: ConversationFeedStyle.divider(context),
                        ),
                      ),
                  ],
                ),
        ),
      );

  Widget _buildArchivedLayout(BuildContext context) {
    final contents = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _buildContents(context),
    );
    if (!editing) return contents;
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConversationSelectionIndicator(selected: selected),
          Expanded(child: contents),
        ],
      ),
    );
  }

  Widget _buildContents(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editing && !archivedLayout)
            Padding(
              padding: const EdgeInsets.only(top: 14, right: 16),
              child: ConversationSelectionIndicator(selected: selected),
            ),
          Padding(
            padding: EdgeInsets.only(bottom: archivedLayout ? 2 : 0),
            child: SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GroupLiveAvatar(
                    groupID: info.groupID,
                    store: logic.groupFeatures,
                    child: AvatarView(
                      width: 54,
                      height: 54,
                      isCircle: true,
                      text: logic.getShowName(info),
                      url: info.faceURL,
                      isGroup: logic.isGroupChat(info),
                      textStyle: Styles.ts_FFFFFF_14sp_medium,
                    ),
                  ),
                  if (logic.getUnreadCount(info) > 0)
                    Positioned(
                      top: -_spacing(archivedLayout && logic.isNotDisturb(info)
                          ? 2.5
                          : 4.5),
                      right: -_spacing(
                          archivedLayout && logic.isNotDisturb(info)
                              ? 2.5
                              : 4.5),
                      child: logic.isNotDisturb(info)
                          ? Container(
                              width: _spacing(10),
                              height: _spacing(10),
                              decoration: BoxDecoration(
                                color: Styles.c_FF381F,
                                shape: BoxShape.circle,
                              ),
                            )
                          : UnreadCountView(
                              count: logic.getUnreadCount(info),
                              size: _spacing(18),
                              fontSize: 10,
                            ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: archivedLayout ? 11 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize:
                          archivedLayout ? MainAxisSize.min : MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: OfficialAccountNameLabel(
                                name: logic.getShowName(info),
                                userID: info.userID,
                                ex: info.ex,
                                isSingleChat: info.isSingleChat,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: ConversationFeedStyle.lineHeight,
                                  fontWeight: FontWeight.w500,
                                  color: AppTokens.textPrimary(
                                      dark: Theme.of(context).brightness ==
                                          Brightness.dark),
                                ),
                              ),
                            ),
                            if (logic.isNotDisturb(info)) ...[
                              SizedBox(width: _spacing(6)),
                              SizedBox(
                                width: archivedLayout ? 18 : null,
                                height: archivedLayout ? 18 : null,
                                child: Icon(Icons.notifications_off,
                                    size: _spacing(16),
                                    color: AppTokens.textSecondary(
                                        dark: Theme.of(context).brightness ==
                                            Brightness.dark)),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: _spacing(6)),
                        MatchTextView(
                          text: logic.getContent(info),
                          textStyle: TextStyle(
                            fontSize: 14,
                            height: ConversationFeedStyle.lineHeight,
                            color: AppTokens.textSecondary(
                                dark: Theme.of(context).brightness ==
                                    Brightness.dark),
                          ),
                          prefixSpan: TextSpan(
                            children: [
                              if (logic.getUnreadCount(info) > 0)
                                TextSpan(
                                  text: '[${sprintf(StrRes.nPieces, [
                                        logic.getUnreadCount(info)
                                      ])}] ',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: AppTokens.textSecondary(
                                          dark: Theme.of(context).brightness ==
                                              Brightness.dark)),
                                ),
                              TextSpan(
                                text: conversationMentionTag(info),
                                style: TextStyle(
                                    fontSize: 14, color: Styles.c_FF381F),
                              ),
                              TextSpan(
                                text: logic.getPrefixTag(info),
                                style: Styles.ts_0089FF_14sp.copyWith(
                                  color: info.draftText?.isNotEmpty == true
                                      ? Styles.c_FF381F
                                      : AppTokens.accent,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: _spacing(8)),
                  Column(
                    mainAxisSize:
                        archivedLayout ? MainAxisSize.min : MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (info.isSingleChat &&
                              info.latestMsg?.sendID ==
                                  OpenIM.iMManager.userID &&
                              info.latestMsg?.status ==
                                  MessageStatus.succeeded) ...[
                            ChatReadReceiptIcon(
                              semanticLabel:
                                  FriendDisplayPreferences.showReadReceipts
                                      ? null
                                      : StrRes.sentSuccessfully,
                              isRead:
                                  FriendDisplayPreferences.showReadReceipts &&
                                      info.latestMsg?.isRead == true,
                              color:
                                  FriendDisplayPreferences.showReadReceipts &&
                                          info.latestMsg?.isRead == true
                                      ? AppTokens.accent
                                      : AppTokens.textSecondary(
                                          dark: Theme.of(context).brightness ==
                                              Brightness.dark),
                            ),
                            SizedBox(width: _spacing(4)),
                          ],
                          Text(
                            logic.getTime(info),
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTokens.textSecondary(
                                    dark: Theme.of(context).brightness ==
                                        Brightness.dark)),
                          ),
                        ],
                      ),
                      if (info.isPinned == true) ...[
                        SizedBox(height: _spacing(4)),
                        Transform.rotate(
                          angle: 0.785398,
                          child: Icon(Icons.push_pin,
                              size: _spacing(16),
                              color: AppTokens.textSecondary(
                                  dark: Theme.of(context).brightness ==
                                      Brightness.dark)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}
