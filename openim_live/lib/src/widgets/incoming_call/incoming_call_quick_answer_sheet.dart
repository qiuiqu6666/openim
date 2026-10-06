import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../models/call_types.dart';

/// A presentation of the existing incoming session, with the shared application
/// sheet and avatar. Expanding leaves the same call and its deadline running.
class IncomingCallQuickAnswerSheet extends StatelessWidget {
  const IncomingCallQuickAnswerSheet({
    super.key,
    required this.userID,
    required this.callType,
    required this.onAccept,
    required this.onReject,
    required this.onExpand,
    this.userInfo,
  });

  final String userID;
  final UserInfo? userInfo;
  final CallType callType;
  final VoidCallback onAccept, onReject, onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final name = userInfo?.remark?.trim().isNotEmpty == true
        ? userInfo!.remark!
        : userInfo?.nickname?.trim().isNotEmpty == true
            ? userInfo!.nickname!
            : userID;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0),
        child: BottomSheetView(
          isOverlaySheet: true,
          useThemeColors: true,
          itemHeight: AppTokens.listItemHeight,
          cancelLabel: chinese ? '打开通话' : 'Open call',
          onCancel: onExpand,
          header: Material(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTokens.rSm)),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Row(children: [
                AvatarView(url: userInfo?.faceURL, text: name),
                const SizedBox(width: AppTokens.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppTokens.s2),
                      Text(
                          callType == CallType.audio
                              ? StrRes.invitedVoiceCallHint
                              : StrRes.invitedVideoCallHint,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          items: [
            SheetItem(
              label: StrRes.pickUp,
              onTap: onAccept,
              textStyle: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            SheetItem(
              label: StrRes.reject,
              onTap: onReject,
              textStyle: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}
