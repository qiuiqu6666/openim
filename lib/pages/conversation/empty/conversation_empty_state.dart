import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Empty feed presentation; the surrounding page keeps its refresh and actions.
class ConversationEmptyState extends StatelessWidget {
  const ConversationEmptyState({
    super.key,
    required this.groupChats,
    this.folderSelected = false,
  });

  static const assetPath =
      'lib/pages/conversation/empty/assets/99chat_empty.png';
  static const _imageAspectRatio = 1445 / 1089;

  final bool groupChats;
  final bool folderSelected;

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final title = folderSelected
        ? (chinese ? '分组内暂无会话' : 'No chats in this folder yet')
        : groupChats
            ? (chinese ? '暂无群聊' : 'No group chats yet')
            : (chinese ? '暂无消息' : 'No messages yet');
    final description = folderSelected
        ? (chinese ? '可将会话添加到此分组' : 'Move chats into this folder')
        : groupChats
            ? (chinese
                ? '点击右上角“+”创建或加入群聊'
                : 'Use + in the top right to create or join a group')
            : (chinese ? '添加好友，开启聊天吧' : 'Add a friend to start chatting');

    return LayoutBuilder(builder: (context, constraints) {
      final imageWidth = (constraints.maxWidth - AppTokens.s8 * 2)
          .clamp(0.0, AppTokens.s8 * 7);
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                AppTokens.s8,
                AppTokens.s8,
                AppTokens.s8,
                AppTokens.s8 + MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: imageWidth,
                    child: AspectRatio(
                      aspectRatio: _imageAspectRatio,
                      child: Image.asset(
                        assetPath,
                        fit: BoxFit.contain,
                        cacheWidth: (imageWidth *
                                MediaQuery.devicePixelRatioOf(context))
                            .ceil(),
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.s5),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: AppTokens.listTitleFontSize,
                          fontWeight: FontWeight.w600,
                          color: AppTokens.textPrimary(dark: dark),
                        ),
                  ),
                  const SizedBox(height: AppTokens.s3),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: AppTokens.captionFontSize,
                          color: AppTokens.textSecondary(dark: dark),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
