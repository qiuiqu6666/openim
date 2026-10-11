import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../settings/widgets/settings_widgets.dart';
import 'recent_call_tokens.dart';
import 'widgets/recent_call_icons.dart';

String recentCallResult(BuildContext context, CallRecords record) {
  String label(String zh, String en) => settingsText(context, zh: zh, en: en);
  if (record.success) {
    final seconds = record.duration < 0 ? 0 : record.duration;
    final time = '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    return '${label('已接通', 'Connected')} · $time';
  }
  return switch (record.state) {
    'rejected' => record.incomingCall
        ? label('已拒接', 'Declined')
        : label('对方已拒接', 'Declined by recipient'),
    'cancelled' => record.incomingCall
        ? label('对方已取消', 'Canceled by caller')
        : label('已取消', 'Canceled'),
    'reject' => label('已拒接', 'Declined'),
    'beRejected' => label('对方已拒接', 'Declined by recipient'),
    'cancel' => label('已取消', 'Canceled'),
    'beCanceled' => label('未接', 'Missed'),
    'timeout' || 'missed' => label('未接', 'Missed'),
    'networkError' => label('连接失败', 'Connection failed'),
    'otherAccepted' => label('已在其他设备接听', 'Answered on another device'),
    'otherReject' => label('已在其他设备拒接', 'Declined on another device'),
    _ => label('未接通', 'Not connected'),
  };
}

String recentCallTime(BuildContext context, CallRecords record,
    {DateTime? now}) {
  if (record.date <= 0) return '';
  final local =
      DateTime.fromMillisecondsSinceEpoch(record.timestampMilliseconds);
  final today = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(local.hour)}:${two(local.minute)}';
  return local.year == today.year
      ? time
      : '${local.year}/${local.month}/${local.day}';
}

class RecentCallTile extends StatelessWidget {
  const RecentCallTile({
    super.key,
    required this.record,
    required this.editing,
    required this.enabled,
    required this.onRedial,
    required this.onProfile,
    required this.onDelete,
  });

  final CallRecords record;
  final bool editing;
  final bool enabled;
  final VoidCallback onRedial;
  final VoidCallback onProfile;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final secondary = AppTokens.textSecondary(dark: dark);
    final resultColor = record.isMissed ? RecentCallTokens.danger : secondary;
    final group = record.roomType == 'group';
    final fallback = group ? record.groupID : record.userID;
    final name = record.nickname.trim().isEmpty ? fallback : record.nickname;
    final direction = settingsText(context,
        zh: record.incomingCall ? '呼入' : '拨出',
        en: record.incomingCall ? 'Incoming' : 'Outgoing');
    final result =
        '${group ? '${settingsText(context, zh: '群通话', en: 'Group call')} · ' : ''}'
        '$direction · ${recentCallResult(context, record)}';
    final time = recentCallTime(context, record);
    final metadataStyle = TextStyle(
        color: resultColor,
        fontSize: RecentCallTokens.metadataSize,
        height: 1.25);
    final timeStyle =
        TextStyle(color: secondary, fontSize: RecentCallTokens.metadataSize);

    return Material(
      color: AppTokens.surface(dark: dark),
      child: InkWell(
        key: ValueKey('recent-call-${record.recordKey}'),
        onTap: enabled && !editing && !group ? onRedial : null,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: RecentCallTokens.rowMinHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                editing ? 0 : AppTokens.s5,
                RecentCallTokens.rowVerticalPadding,
                AppTokens.s5,
                RecentCallTokens.rowVerticalPadding),
            child: LayoutBuilder(builder: (context, constraints) {
              final compact = MediaQuery.sizeOf(context).width <
                      RecentCallTokens.compactWidth ||
                  MediaQuery.textScalerOf(context).scale(1) >
                      RecentCallTokens.compactTextScale;
              return Row(children: [
                if (editing)
                  IconButton(
                    key: ValueKey('recent-call-delete-${record.recordKey}'),
                    tooltip: settingsText(context,
                        zh: '隐藏通话记录', en: 'Hide call record'),
                    padding: const EdgeInsets.only(left: AppTokens.s2),
                    constraints: const BoxConstraints.tightFor(
                        width: RecentCallTokens.tapExtent,
                        height: RecentCallTokens.tapExtent),
                    onPressed: enabled ? onDelete : null,
                    icon: Container(
                      width: RecentCallTokens.mediaIconSize,
                      height: RecentCallTokens.mediaIconSize,
                      decoration: const BoxDecoration(
                          color: RecentCallTokens.danger,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.remove_rounded,
                          color: AppTokens.onAccent,
                          size: RecentCallTokens.deleteIconSize),
                    ),
                  ),
                RecentCallMediaIcon(
                    video: record.type.toLowerCase() == 'video',
                    color: secondary),
                const SizedBox(width: RecentCallTokens.mediaGap),
                AvatarView(
                  width: RecentCallTokens.avatarSize,
                  height: RecentCallTokens.avatarSize,
                  text: name,
                  url: record.faceURL,
                  textStyle: const TextStyle(
                      color: AppTokens.onAccent,
                      fontSize: RecentCallTokens.nameSize),
                ),
                const SizedBox(width: RecentCallTokens.avatarGap),
                Expanded(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: record.isMissed
                                ? RecentCallTokens.danger
                                : AppTokens.textPrimary(dark: dark),
                            fontSize: RecentCallTokens.nameSize,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: RecentCallTokens.metadataGap),
                    Text(result,
                        maxLines: compact ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: metadataStyle),
                    if (compact && (time.isNotEmpty || !group)) ...[
                      const SizedBox(height: RecentCallTokens.metadataGap),
                      Row(children: [
                        Expanded(child: Text(time, style: timeStyle)),
                        if (!group) _profileAction(context, secondary),
                      ]),
                    ],
                  ],
                )),
                if (!compact) ...[
                  const SizedBox(width: AppTokens.s4),
                  if (group)
                    Text(time, style: timeStyle)
                  else
                    _profileAction(context, secondary,
                        time: Text(time, style: timeStyle)),
                ],
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _profileAction(BuildContext context, Color secondary, {Widget? time}) {
    final canOpen = enabled && record.userID.trim().isNotEmpty;
    return Semantics(
      button: true,
      enabled: canOpen,
      label: settingsText(context, zh: '查看资料', en: 'View profile'),
      child: InkWell(
        key: ValueKey('recent-call-profile-${record.recordKey}'),
        onTap: canOpen ? onProfile : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minWidth: RecentCallTokens.tapExtent,
              minHeight: RecentCallTokens.tapExtent),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (time != null) ...[
                  time,
                  const SizedBox(height: RecentCallTokens.actionGap),
                ],
                Icon(Icons.info_outline_rounded,
                    color: canOpen ? AppTokens.accent : secondary,
                    size: RecentCallTokens.actionIconSize),
              ]),
        ),
      ),
    );
  }
}
