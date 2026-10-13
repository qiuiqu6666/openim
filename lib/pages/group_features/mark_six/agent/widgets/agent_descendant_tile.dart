// Agent card shared by the authorized descendant list and details.
// Retains the existing visual metrics and supports both old and new callers.
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../widgets/mark_six_style.dart';
import '../identity/agent_avatar_directory.dart';
import '../identity/agent_user_avatar.dart';

class AgentDescendantTile extends StatelessWidget {
  const AgentDescendantTile({
    super.key,
    required this.item,
    required this.onTap,
    this.avatars,
    this.depth = 0,
  });

  final Map<String, dynamic> item;
  final AgentAvatarDirectory? avatars;
  final VoidCallback onTap;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final name =
        '${item['displayName'] ?? item['nickname'] ?? item['playerNo'] ?? item['userId']}';
    final profit = num.tryParse('${item['playerProfitLoss']}');
    final fallback = _first(item, const ['avatarUrl', 'avatarURL', 'faceURL', 'faceUrl']);
    return Padding(
      padding: EdgeInsets.only(left: depth.clamp(0, 4) * 12.0, bottom: 8),
      child: Material(
        color: style.surface,
        borderRadius: BorderRadius.circular(MarkSixStyle.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(MarkSixStyle.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (avatars != null)
                AgentUserAvatar(directory: avatars!, item: item, name: name)
              else
                AvatarView(width: 40, height: 40, text: name, url: fallback),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(name, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: style.text, fontSize: 16,
                        fontWeight: FontWeight.w600))),
                    if (item['isAgent'] == true)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: style.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(8)),
                        child: Text('代理', style: TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w600, color: style.primary))),
                  ]),
                  const SizedBox(height: 4),
                  Text('用户编号：${item['playerNo'] ?? '—'}',
                    style: TextStyle(fontSize: 12, color: style.secondary)),
                  const SizedBox(height: 4),
                  Text('总积分：${markSixAmount(item['balance'])}',
                    style: TextStyle(fontSize: 12, color: style.primary)),
                  const SizedBox(height: 4),
                  Text('输赢 ${markSixAmount(profit)}  ·  流水 ${markSixAmount(item['totalFlow'])}',
                    style: TextStyle(fontSize: 12,
                      color: profit != null && profit < 0
                          ? style.error : style.primary)),
                ],
              )),
              Icon(Icons.chevron_right_rounded, color: style.secondary),
            ]),
          ),
        ),
      ),
    );
  }

  static String? _first(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
