import 'package:openim_common/localization.dart';
// Card visuals and hierarchy indentation based on 99CHAT's
// agent_rebate_descendants_page.dart. The verified OpenIM avatar is retained.
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
    this.relationText,
  });

  final Map<String, dynamic> item;
  final AgentAvatarDirectory? avatars;
  final VoidCallback onTap;
  final int depth;
  final String? relationText;

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final name =
        _first(item, const ['displayName', 'nickname', 'playerNo', 'userId']) ??
            '—';
    final profit = num.tryParse('${item['playerProfitLoss'] ?? ''}') ?? 0;
    final fallback =
        _first(item, const ['avatarUrl', 'avatarURL', 'faceURL', 'faceUrl']);
    final relation = relationText?.trim() ?? '';
    // Preserve the actual level in the projection. Cap *visual* indentation to
    // keep fourth-level-and-deeper rows usable on small iPhone screens.
    final indent = depth.clamp(0, 4).toDouble() * 20.0;
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 12),
      child: Material(
        color: style.surface,
        borderRadius: BorderRadius.circular(MarkSixStyle.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(MarkSixStyle.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (avatars != null)
                AgentUserAvatar(
                    directory: avatars!, item: item, name: name, size: 48)
              else
                AvatarView(width: 48, height: 48, text: name, url: fallback),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: style.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600))),
                        if (item['isAgent'] == true) ...[
                          const SizedBox(width: 8),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: style.primary.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text('代理',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: style.primary))),
                        ],
                      ]),
                      const SizedBox(height: 8),
                      Text(AppCopy.format('编号 {#0}', [item['playerNo'] ?? '—']),
                          style:
                              TextStyle(fontSize: 12, color: style.secondary)),
                      const SizedBox(height: 8),
                      Text(
                          AppCopy.format(
                              '总积分 {#0}', [markSixAmount(item['balance'])]),
                          style: TextStyle(fontSize: 12, color: style.primary)),
                      const SizedBox(height: 8),
                      Text(
                          AppCopy.format('用户输赢 {#0}  今日流水 {#1}', [
                            markSixAmount(profit),
                            markSixAmount(item['totalFlow'])
                          ]),
                          style: TextStyle(
                              fontSize: 12,
                              color: profit < 0 ? style.error : style.primary)),
                      if (relation.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(relation,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: style.secondary)),
                      ],
                    ]),
              ),
              const SizedBox(width: 6),
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
