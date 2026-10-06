import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../chat_history_search_tokens.dart';
import 'chat_history_search_layout.dart';

/// Search summaries open the existing message context for playback/file actions.
/// Voice rows deliberately do not download every audio file while browsing.
class ChatHistoryResultTile extends StatelessWidget {
  const ChatHistoryResultTile(
      {super.key,
      required this.message,
      required this.onTap,
      this.showVoiceDetails = false,
      this.horizontalPadding = 0.0,
      this.showDivider = false});
  final Message message;
  final VoidCallback onTap;
  final bool showVoiceDetails;
  final double horizontalPadding;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    if (showVoiceDetails && message.contentType == MessageType.voice) {
      return _voice(context);
    }
    if (message.hasExpired) return _resultNotice(context, 'sdkExpired'.tr);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final desktop = chatHistorySearchIsDesktop(context);
    final avatarSize = desktop
        ? ChatHistorySearchTokens.desktopAvatarSize
        : ChatHistorySearchTokens.avatarSize;
    final name = message.senderNickname?.trim();
    final sender =
        name?.isNotEmpty == true ? name! : message.sendID?.trim() ?? '';
    final time = message.sendTime;
    final stamp = time == null ? '' : formatChatMessageTime(context, time);
    final summary = IMUtils.parseMsg(message);
    final preview = Text(
      summary,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: ChatHistorySearchTokens.previewFontSize,
        height: ChatHistorySearchTokens.previewHeight,
        color: AppTokens.textSecondary(dark: dark),
      ),
    );
    final tile = Material(
      color: AppTokens.surface(dark: dark),
      child: InkWell(
        onTap: () {
          if (!message.hasExpired) onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: ChatHistorySearchTokens.rowHeight(context,
                        desktop: desktop) -
                    ChatHistorySearchTokens.dividerThickness,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: ChatHistorySearchTokens.rowVerticalPadding),
                child: Row(
                  children: [
                    AvatarView(
                      url: message.senderFaceUrl,
                      text: sender,
                      width: avatarSize,
                      height: avatarSize,
                      isCircle: true,
                      textStyle: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: ChatHistorySearchTokens.titleFontSize,
                        color: AppTokens.onAccent,
                      ),
                    ),
                    const SizedBox(
                        width: ChatHistorySearchTokens.avatarTextGap),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) => Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    sender,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontSize:
                                          ChatHistorySearchTokens.titleFontSize,
                                      height:
                                          ChatHistorySearchTokens.titleHeight,
                                      fontWeight: FontWeight.w500,
                                      color: AppTokens.textPrimary(dark: dark),
                                    ),
                                  ),
                                ),
                                if (stamp.isNotEmpty)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: constraints.maxWidth *
                                          ChatHistorySearchTokens
                                              .timeMaxWidthRatio,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: AppTokens.s3),
                                      child: Text(
                                        stamp,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontSize: ChatHistorySearchTokens
                                              .timeFontSize,
                                          color: AppTokens.textSecondary(
                                              dark: dark),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (summary.isNotEmpty) ...[
                            const SizedBox(
                                height: ChatHistorySearchTokens.textGap),
                            desktop ? SelectionArea(child: preview) : preview,
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showDivider)
              Divider(
                height: ChatHistorySearchTokens.dividerThickness,
                thickness: ChatHistorySearchTokens.dividerThickness,
                indent: horizontalPadding +
                    avatarSize +
                    ChatHistorySearchTokens.avatarTextGap,
                color: ChatHistorySearchTokens.divider(dark: dark),
              ),
          ],
        ),
      ),
    );
    return message.attachedInfoElem?.isPrivateChat == true
        ? ChatExpiringContent(
            message: message,
            child: tile,
            builder: (context, content, notice) => notice == null
                ? _resultNotice(context, 'sdkExpired'.tr)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [content, _resultNotice(context, notice)],
                  ),
          )
        : tile;
  }

  Widget _resultNotice(BuildContext context, String text) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: ChatHistorySearchTokens.rowVerticalPadding),
        child: Text(text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: ChatHistorySearchTokens.previewFontSize,
                color: AppTokens.textSecondary(
                    dark: Theme.of(context).brightness == Brightness.dark))),
      );

  Widget _voice(BuildContext context) {
    if (message.hasExpired) return _voiceNotice(context, 'sdkExpired'.tr);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final duration = message.soundElem?.duration;
    final name = message.senderNickname?.trim();
    final sender =
        name?.isNotEmpty == true ? name! : message.sendID?.trim() ?? '';
    final time = message.sendTime;
    final stamp = time == null ? '' : formatChatMessageTime(context, time);
    final tile = Material(
      color: AppTokens.surface(dark: dark),
      clipBehavior: Clip.hardEdge,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s5,
            vertical: ChatHistoryFileTokens.rowVerticalPadding),
        onTap: () {
          if (!message.hasExpired) onTap();
        },
        leading: const SizedBox.square(
          dimension: ChatHistoryFileTokens.iconExtent,
          child: Icon(Icons.mic_rounded,
              size: AppTokens.chevronSize, color: AppTokens.accent),
        ),
        title: Text.rich(
          TextSpan(children: [
            TextSpan(text: StrRes.voice),
            if (duration != null && duration > 0)
              TextSpan(
                  text: '  $duration ${StrRes.seconds}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: ChatHistoryFileTokens.titleFontSize,
              color: AppTokens.textPrimary(dark: dark)),
        ),
        subtitle: sender.isEmpty && stamp.isEmpty
            ? null
            : _voiceMetadata(context, sender, stamp),
        trailing: Icon(Icons.chevron_right_rounded,
            size: AppTokens.chevronSize,
            color: AppTokens.textSecondary(dark: dark)),
      ),
    );
    return message.attachedInfoElem?.isPrivateChat == true
        ? ChatExpiringContent(
            message: message,
            child: tile,
            builder: (context, content, notice) => notice == null
                ? _voiceNotice(context, 'sdkExpired'.tr)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [content, _voiceNotice(context, notice)],
                  ),
          )
        : tile;
  }

  Widget _voiceMetadata(BuildContext context, String sender, String stamp) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
        fontSize: ChatHistoryFileTokens.timeFontSize,
        color:
            AppTokens.textSecondary(dark: theme.brightness == Brightness.dark));
    // Large text keeps the timestamp on its own line rather than squeezing it
    // between a long sender name and the navigation chevron.
    if (MediaQuery.textScalerOf(context)
            .scale(ChatHistoryFileTokens.timeFontSize) >
        AppTokens.listTitleFontSize) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sender.isNotEmpty)
            Text(sender,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          if (stamp.isNotEmpty)
            Text(stamp,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sender.isNotEmpty)
          Expanded(
              flex: 3,
              child: Text(sender,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        if (sender.isNotEmpty && stamp.isNotEmpty)
          const SizedBox(width: AppTokens.s3),
        if (stamp.isNotEmpty)
          Flexible(
              flex: 2,
              child: Text(stamp,
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: style)),
      ],
    );
  }

  Widget _voiceNotice(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s5,
            vertical: ChatHistoryFileTokens.rowVerticalPadding),
        child: Text(text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: ChatHistoryFileTokens.timeFontSize,
                color: AppTokens.textSecondary(
                    dark: Theme.of(context).brightness == Brightness.dark))),
      );
}
