import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../settings/widgets/settings_widgets.dart';
import 'recent_call_tokens.dart';

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
  final date = DateTime(local.year, local.month, local.day);
  final currentDate = DateTime(today.year, today.month, today.day);
  if (date == currentDate) return time;
  if (date == DateTime(today.year, today.month, today.day - 1)) {
    return '${settingsText(context, zh: '昨天', en: 'Yesterday')} $time';
  }
  final prefix = local.year == today.year ? '' : '${local.year}/';
  return '$prefix${two(local.month)}/${two(local.day)} $time';
}

class RecentCallTile extends StatelessWidget {
  const RecentCallTile({
    super.key,
    required this.record,
    required this.editing,
    required this.enabled,
    required this.onRedial,
    required this.onDelete,
  });

  final CallRecords record;
  final bool editing;
  final bool enabled;
  final VoidCallback onRedial;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final secondary = AppTokens.textSecondary(dark: dark);
    final resultColor = record.isMissed ? settingsDanger(dark) : secondary;
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
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s5,
                vertical: RecentCallTokens.rowVerticalPadding),
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
                    color: settingsDanger(dark),
                    constraints: const BoxConstraints.tightFor(
                        width: RecentCallTokens.tapExtent,
                        height: RecentCallTokens.tapExtent),
                    onPressed: enabled ? onDelete : null,
                    icon: const Icon(Icons.remove_circle,
                        size: RecentCallTokens.mediaIconSize),
                  ),
                Icon(
                    record.type == 'video'
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    color: resultColor,
                    size: RecentCallTokens.mediaIconSize),
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
                                ? settingsDanger(dark)
                                : AppTokens.textPrimary(dark: dark),
                            fontSize: RecentCallTokens.nameSize,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: RecentCallTokens.metadataGap),
                    Text(result,
                        maxLines: compact ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: metadataStyle),
                    if (compact && time.isNotEmpty) ...[
                      const SizedBox(height: RecentCallTokens.metadataGap),
                      Text(time, style: timeStyle),
                    ],
                  ],
                )),
                if (!compact) ...[
                  const SizedBox(width: AppTokens.s4),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(time, style: timeStyle),
                    if (!editing && !group)
                      IconButton(
                        key: ValueKey('recent-call-redial-${record.recordKey}'),
                        tooltip:
                            settingsText(context, zh: '重拨', en: 'Call again'),
                        constraints: const BoxConstraints.tightFor(
                            width: RecentCallTokens.tapExtent,
                            height: RecentCallTokens.tapExtent),
                        onPressed: enabled ? onRedial : null,
                        icon: const Icon(Icons.info_outline,
                            color: AppTokens.accent,
                            size: RecentCallTokens.actionIconSize),
                      ),
                  ]),
                ],
              ]);
            }),
          ),
        ),
      ),
    );
  }
}
