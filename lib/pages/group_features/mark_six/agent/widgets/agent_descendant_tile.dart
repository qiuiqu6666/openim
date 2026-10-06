// Geometry adapted from 99chat _DescendantTile.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../widgets/mark_six_style.dart';

class AgentDescendantTile extends StatelessWidget {
  const AgentDescendantTile(
      {super.key, required this.item, required this.onTap, this.depth = 0});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final int depth;
  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final name =
        '${item['displayName'] ?? item['nickname'] ?? item['playerNo'] ?? item['userId']}';
    final profit = num.tryParse('${item['playerProfitLoss']}');
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
                      AvatarView(
                          width: 40,
                          height: 40,
                          text: name,
                          url: '${item['avatarUrl'] ?? item['faceURL'] ?? ''}'),
                      const SizedBox(width: 12),
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
                              if (item['isAgent'] == true)
                                Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: style.primary
                                            .withValues(alpha: .12),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text('代理',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: style.primary)))
                            ]),
                            const SizedBox(height: 4),
                            Text('用户编号：${item['playerNo'] ?? '—'}',
                                style: TextStyle(
                                    fontSize: 12, color: style.secondary)),
                            const SizedBox(height: 4),
                            Text('总积分：${markSixAmount(item['balance'])}',
                                style: TextStyle(
                                    fontSize: 12, color: style.primary)),
                            const SizedBox(height: 4),
                            Text(
                                '输赢 ${markSixAmount(profit)}  ·  流水 ${markSixAmount(item['totalFlow'])}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: profit != null && profit < 0
                                        ? style.error
                                        : style.primary)),
                          ])),
                      Icon(Icons.chevron_right_rounded, color: style.secondary),
                    ])))));
  }
}
