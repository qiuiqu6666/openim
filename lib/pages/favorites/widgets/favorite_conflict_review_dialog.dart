import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import '../../mine/settings/widgets/settings_widgets.dart';

/// Reviewing never saves. Accepting only permits a later explicit save against
/// the reviewed version; both texts remain visible for that decision.
Future<bool> showFavoriteConflictReview(BuildContext context,
    {required FavoriteItem currentItem,
    required String editedText,
    FavoriteRepository? repository}) async {
  final scope = repository?.sessionScope;
  final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        Widget content() {
          final current = repository == null ||
              (repository.isSessionCurrent(scope!) && repository.available);
          final pureText = currentItem.kind == FavoriteKind.note &&
              currentItem.content != null &&
              currentItem.blocks.every((block) => block.type == 'text');
          final textColor = settingsTextColor(context);
          String text(String zh, String en) =>
              settingsText(context, zh: zh, en: en);
          return AlertDialog(
              key: const ValueKey('favorite-conflict-review'),
              backgroundColor:
                  AppTokens.surfaceAlt(dark: settingsIsDark(context)),
              scrollable: true,
              title: Text(text('查看最新版本', 'Review latest version')),
              content: !current
                  ? Text(text('登录或收藏服务状态已改变，请重新打开收藏',
                      'Your account or favorite service changed. Reopen favorites.'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(
                              text('服务器最新版本（${currentItem.version}）',
                                  'Latest server version (${currentItem.version})'),
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: AppTokens.s3),
                          SelectableText(currentItem.text,
                              key: const ValueKey('favorite-conflict-latest'),
                              style: TextStyle(color: textColor)),
                          const SizedBox(height: AppTokens.s5),
                          Text(text('我的编辑', 'My edits'),
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: AppTokens.s3),
                          SelectableText(editedText,
                              key: const ValueKey('favorite-conflict-edited'),
                              style: TextStyle(color: textColor)),
                          const SizedBox(height: AppTokens.s5),
                          Text(
                              pureText
                                  ? text('继续会保留你的正文。审阅不会保存，再次点击“完成”才会提交。',
                                      'Your edits will be kept. Reviewing does not save; tap Done again to submit.')
                                  : text('最新版本包含其他内容，不能用纯文字覆盖。你的编辑仍保留在编辑页。',
                                      'The latest version contains other content and cannot be replaced by plain text. Your edits remain in the editor.'),
                              style: TextStyle(
                                  color: settingsSecondaryTextColor(context))),
                        ]),
              actions: [
                TextButton(
                    key: const ValueKey('favorite-conflict-cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(text('返回编辑', 'Back to editor'))),
                FilledButton(
                    key: const ValueKey('favorite-conflict-accept'),
                    onPressed: current && pureText
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: Text(text('保留我的编辑继续', 'Keep my edits'))),
              ]);
        }

        return repository == null
            ? content()
            : AnimatedBuilder(
                animation: repository, builder: (_, __) => content());
      });
  return result == true;
}
