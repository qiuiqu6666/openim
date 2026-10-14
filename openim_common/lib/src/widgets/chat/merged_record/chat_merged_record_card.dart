import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Shared by live chat and nested merged-history views. The message container
/// owns delivery state and menus; this card only lays out their presentation.
class ChatMergedRecordCard extends StatelessWidget {
  const ChatMergedRecordCard(
      {super.key,
      required this.title,
      required this.summaries,
      required this.isOutgoing,
      required this.onTap,
      this.time,
      this.status});
  final String title;
  final List<String> summaries;
  final bool isOutgoing;
  final VoidCallback onTap;
  final String? time;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTokens.textPrimary(dark: dark);
    final secondary = ChatMergedRecordTokens.secondary(dark);
    final metadata = Row(mainAxisSize: MainAxisSize.min, children: [
      if (time != null)
        Text(time!,
            style: TextStyle(
                color: secondary,
                fontSize: ChatMergedRecordTokens.metadataSize)),
      if (status != null) ...[
        const SizedBox(width: AppTokens.s2),
        Flexible(child: status!),
      ],
    ]);
    return SizedBox(
        width: ChatMergedRecordTokens.width,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                  key: const ValueKey('merged-record-surface'),
                  color: ChatMergedRecordTokens.background(
                      dark: dark, outgoing: isOutgoing),
                  borderRadius: BorderRadius.circular(AppTokens.rMd),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                      onTap: onTap,
                      child: Padding(
                          padding: const EdgeInsets.all(AppTokens.s5),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    title.trim().isEmpty
                                        ? StrRes.chatRecord
                                        : title,
                                    key: const ValueKey('merged-record-title'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: primary,
                                        fontSize:
                                            ChatMergedRecordTokens.titleSize,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4)),
                                if (summaries.isNotEmpty) ...[
                                  const SizedBox(height: AppTokens.s3),
                                  for (final summary in summaries.take(3))
                                    Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: AppTokens.s2),
                                        child: Text(summary,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: secondary,
                                                fontSize: ChatMergedRecordTokens
                                                    .summarySize,
                                                height: 1.45))),
                                ],
                                const SizedBox(height: AppTokens.s4),
                                Divider(
                                    height: 1,
                                    color: primary.withValues(alpha: .1)),
                                const SizedBox(height: AppTokens.s4),
                                Row(children: [
                                  Expanded(
                                      child: Text(StrRes.chatRecord,
                                          style: TextStyle(
                                              color: secondary,
                                              fontSize: ChatMergedRecordTokens
                                                  .summarySize))),
                                  Icon(Icons.chevron_right,
                                      size: AppTokens.s6, color: secondary)
                                ]),
                                if (isOutgoing &&
                                    (time != null || status != null)) ...[
                                  const SizedBox(height: AppTokens.s4),
                                  Align(
                                      alignment: Alignment.centerRight,
                                      child: metadata),
                                ],
                              ])))),
              if (!isOutgoing && time != null) ...[
                const SizedBox(height: AppTokens.s2),
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppTokens.s2),
                    child: metadata),
              ],
            ]));
  }
}

class ChatMergedRecordTokens {
  ChatMergedRecordTokens._();
  static const width = 285.0;
  static const titleSize = 16.0;
  static const summarySize = 13.0;
  static const metadataSize = 12.0;
  static Color secondary(bool dark) =>
      dark ? const Color(0xFFB5BEC8) : const Color(0xFF626D79);
  static Color background({required bool dark, required bool outgoing}) => dark
      ? (outgoing ? const Color(0xFF24384B) : const Color(0xFF25272C))
      : (outgoing ? ChatBubbleTokens.outgoingLight : AppTokens.surfaceLight);
}
