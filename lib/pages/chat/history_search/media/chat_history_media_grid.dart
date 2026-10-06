import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../media/widgets/chat_video_thumbnail.dart';

/// The same compact media grid for the separate picture and video categories.
class ChatHistoryMediaGrid extends StatelessWidget {
  const ChatHistoryMediaGrid({
    super.key,
    required this.messages,
    required this.onTap,
    required this.footer,
  });

  final List<Message> messages;
  final ValueChanged<Message> onTap;
  final Widget footer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
          key: const PageStorageKey('chat-history-results-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(ChatHistoryMediaTokens.gap),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth >=
                          ChatHistoryMediaTokens.wideBreakpoint
                      ? ChatHistoryMediaTokens.wideColumns
                      : ChatHistoryMediaTokens.compactColumns,
                  crossAxisSpacing: ChatHistoryMediaTokens.gap,
                  mainAxisSpacing: ChatHistoryMediaTokens.gap,
                ),
                itemCount: messages.length,
                itemBuilder: (context, index) => _MediaCell(
                  key: ValueKey(
                      'chat-history-result-${messages[index].clientMsgID}'),
                  message: messages[index],
                  onTap: () => onTap(messages[index]),
                ),
              ),
            ),
            SliverToBoxAdapter(child: footer),
          ],
        ),
      );
}

class _MediaCell extends StatelessWidget {
  const _MediaCell({super.key, required this.message, required this.onTap});

  final Message message;
  final VoidCallback onTap;

  String? get _thumbnailUrl {
    final candidates = message.contentType == MessageType.video
        ? [message.videoElem?.snapshotUrl]
        : [
            message.pictureElem?.snapshotPicture?.url,
            message.pictureElem?.bigPicture?.url,
            message.pictureElem?.sourcePicture?.url,
          ];
    for (final url in candidates) {
      if (url != null && url.trim().isNotEmpty) return url.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final video = message.contentType == MessageType.video;
    final child = Semantics(
      button: true,
      label: IMUtils.parseMsg(message),
      child: Stack(fit: StackFit.expand, children: [
        LayoutBuilder(
          builder: (context, constraints) => ChatVideoThumbnail(
            path: video
                ? message.videoElem?.snapshotPath
                : message.pictureElem?.sourcePath,
            url: _thumbnailUrl,
            width: constraints.maxWidth,
          ),
        ),
        if (video)
          Center(
            child: Icon(Icons.play_circle_fill,
                size: ChatHistoryMediaTokens.playIconSize,
                color: AppTokens.onAccent
                    .withValues(alpha: ChatHistoryMediaTokens.playIconOpacity)),
          ),
        // Paint feedback above the image and clip it to this grid cell.
        Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.hardEdge,
          child: InkWell(onTap: () {
            if (!message.hasExpired) onTap();
          }),
        ),
      ]),
    );
    return RepaintBoundary(
      child: ClipRect(
        child: ColoredBox(
          color: scheme.surfaceContainerLow,
          child: message.attachedInfoElem?.isPrivateChat == true
              ? ChatExpiringContent(
                  message: message,
                  child: child,
                  builder: (context, content, notice) => notice == null
                      ? Center(child: content)
                      : Stack(fit: StackFit.expand, children: [
                          content,
                          PositionedDirectional(
                            start: 0,
                            end: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: scheme.surfaceContainerHigh,
                                child: Padding(
                                  padding: const EdgeInsets.all(AppTokens.s2),
                                  child: Text(notice,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                              color: scheme.onSurfaceVariant)),
                                ),
                              ),
                            ),
                          ),
                        ]),
                )
              : child,
        ),
      ),
    );
  }
}
