import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// File search reuses the chat attachment's cache/open/retry flow with a list
/// presentation. Private attachments first return to their original message.
class ChatHistoryFileTile extends StatelessWidget {
  const ChatHistoryFileTile({
    super.key,
    required this.message,
    required this.onPrivateTap,
    this.canOpen,
  });

  final Message message;
  final VoidCallback onPrivateTap;
  final bool Function()? canOpen;
  static const _padding = EdgeInsets.symmetric(
      horizontal: AppTokens.s5,
      vertical: ChatHistoryFileTokens.rowVerticalPadding);

  @override
  Widget build(BuildContext context) {
    if (message.hasExpired) {
      return _expired(context);
    }
    if (message.attachedInfoElem?.isPrivateChat == true) {
      return ChatExpiringContent(
        message: message,
        child: _row(context, onTap: onPrivateTap),
        builder: (context, content, notice) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notice == null)
              _expired(context)
            else ...[
              content,
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTokens.s5, 0,
                    AppTokens.s5, ChatHistoryFileTokens.rowVerticalPadding),
                child: Text(notice,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: ChatHistoryFileTokens.timeFontSize,
                        color: AppTokens.textSecondary(
                            dark: Theme.of(context).brightness ==
                                Brightness.dark))),
              ),
            ],
          ],
        ),
      );
    }
    return ChatFileMessageView(
      message: message,
      builder: (context,
              {required downloaded,
              required busy,
              required failed,
              required progress,
              required onOpen}) =>
          _row(context,
              downloaded: downloaded,
              busy: busy,
              failed: failed,
              progress: progress,
              onTap: onOpen),
    );
  }

  Widget _expired(BuildContext context) => Padding(
        padding: _padding,
        child: Text('sdkExpired'.tr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: ChatHistoryFileTokens.timeFontSize,
                color: AppTokens.textSecondary(
                    dark: Theme.of(context).brightness == Brightness.dark))),
      );

  Widget _row(
    BuildContext context, {
    required VoidCallback onTap,
    bool downloaded = false,
    bool busy = false,
    bool failed = false,
    double? progress,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final time = message.sendTime;
    final stamp = time == null ? '' : formatChatMessageTime(context, time);
    final name = message.fileElem?.fileName?.trim();
    final fileName = name?.isNotEmpty == true ? name! : 'attachmentFile'.tr;
    final action = failed
        ? 'attachmentRetry'.tr
        : downloaded
            ? 'attachmentOpen'.tr
            : 'attachmentDownload'.tr;
    return Semantics(
      button: true,
      enabled: !busy,
      label: '$fileName, ${busy ? 'attachmentLoading'.tr : action}',
      child: Material(
        color: AppTokens.surface(dark: dark),
        clipBehavior: Clip.hardEdge,
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: _padding,
          onTap: busy
              ? null
              : () {
                  if (!message.hasExpired && (canOpen?.call() ?? true)) {
                    onTap();
                  }
                },
          leading: SizedBox.square(
            dimension: ChatHistoryFileTokens.iconExtent,
            child: Icon(
                downloaded
                    ? Icons.insert_drive_file_rounded
                    : Icons.file_download_outlined,
                size: AppTokens.chevronSize,
                color: downloaded
                    ? AppTokens.accent
                    : AppTokens.textSecondary(dark: dark)),
          ),
          title: Text(fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: ChatHistoryFileTokens.titleFontSize,
                  color: AppTokens.textPrimary(dark: dark))),
          subtitle: stamp.isEmpty && !failed
              ? null
              : Text(failed ? 'attachmentRetry'.tr : stamp,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: ChatHistoryFileTokens.timeFontSize,
                      color: failed
                          ? theme.colorScheme.error
                          : AppTokens.textSecondary(dark: dark))),
          trailing: busy
              ? SizedBox.square(
                  dimension: ChatHistoryFileTokens.progressExtent,
                  child: CircularProgressIndicator(
                      value: progress,
                      backgroundColor: ChatComposerTokens.divider(dark: dark),
                      strokeWidth: ChatHistoryFileTokens.progressStroke,
                      color: AppTokens.accent))
              : null,
        ),
      ),
    );
  }
}
