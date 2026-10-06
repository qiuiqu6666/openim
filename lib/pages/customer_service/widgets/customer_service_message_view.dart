import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../customer_service_tokens.dart';
import '../models/customer_service_chat_entry.dart';

class CustomerServiceMessageView extends StatelessWidget {
  const CustomerServiceMessageView({
    super.key,
    required this.entry,
    required this.onRetry,
    required this.onOpenMedia,
  });

  final CustomerServiceChatEntry entry;
  final VoidCallback onRetry;
  final void Function(
      {required String url,
      required String path,
      required String thumbnail,
      required bool video,
      required String name,
      required bool file}) onOpenMedia;

  @override
  Widget build(BuildContext context) {
    if (entry.system) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Text(entry.content,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: CustomerServiceTokens.secondaryText(context),
                fontSize: CustomerServiceTokens.chipFontSize)),
      );
    }
    final textColor = entry.outgoing
        ? AppTokens.onAccent
        : CustomerServiceTokens.text(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s4, vertical: AppTokens.s2),
      child: Align(
        alignment:
            entry.outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: LayoutBuilder(builder: (_, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: constraints.maxWidth *
                    CustomerServiceTokens.messageMaxWidthFactor),
            child: Column(
              crossAxisAlignment: entry.outgoing
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: entry.outgoing
                      ? CustomerServiceTokens.blue
                      : CustomerServiceTokens.surface(context),
                  borderRadius:
                      BorderRadius.circular(CustomerServiceTokens.cardRadius),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry.content.isNotEmpty)
                          SelectableText(entry.content,
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: CustomerServiceTokens.faqFontSize,
                                  height:
                                      CustomerServiceTokens.answerLineHeight)),
                        for (final attachment in entry.attachments) ...[
                          if (entry.content.isNotEmpty)
                            const SizedBox(height: AppTokens.s3),
                          _media(context,
                              url: attachment.dataUrl,
                              thumbnail: attachment.thumbUrl,
                              path: '',
                              kind: attachment.fileType,
                              name: attachment.fileName),
                        ],
                        if (entry.attachments.isEmpty && entry.upload != null)
                          _media(context,
                              url: '',
                              path: entry.upload!.path,
                              thumbnail: entry.upload!.thumbnailPath,
                              kind: entry.upload!.fileType,
                              name: entry.upload!.filename),
                      ],
                    ),
                  ),
                ),
                if (entry.outgoing &&
                    entry.state != CustomerServiceSendState.sent)
                  entry.state == CustomerServiceSendState.failed
                      ? TextButton.icon(
                          key: ValueKey(
                              'customer-service-retry-${entry.echoId}'),
                          onPressed: onRetry,
                          icon: const Icon(Icons.error_outline_rounded),
                          label: Text(
                              Localizations.localeOf(context).languageCode ==
                                      'zh'
                                  ? '发送失败，点击重试'
                                  : 'Send failed. Retry'),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(AppTokens.s2),
                          child: Text(
                              Localizations.localeOf(context).languageCode ==
                                      'zh'
                                  ? '发送中…'
                                  : 'Sending…',
                              style: TextStyle(
                                  color: CustomerServiceTokens.secondaryText(
                                      context),
                                  fontSize:
                                      CustomerServiceTokens.chipFontSize)),
                        ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _media(BuildContext context,
      {required String url,
      required String path,
      required String thumbnail,
      required String kind,
      required String name}) {
    final video = kind == 'video';
    final image = kind == 'image';
    return InkWell(
      onTap: () => onOpenMedia(
          url: url,
          path: path,
          thumbnail: thumbnail,
          video: video,
          name: name,
          file: !image && !video),
      child: !image && !video
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.insert_drive_file_outlined),
              const SizedBox(width: AppTokens.s3),
              Flexible(child: Text(name)),
            ])
          : SizedBox(
              width: CustomerServiceTokens.mediaWidth,
              height: CustomerServiceTokens.mediaHeight,
              child: Stack(fit: StackFit.expand, children: [
                if (path.isNotEmpty && image)
                  Image.file(File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _placeholder(context))
                else if ((video ? thumbnail : url).startsWith('http'))
                  ImageUtil.networkImage(
                      url: video ? thumbnail : url,
                      fit: BoxFit.contain,
                      errorWidget: _placeholder(context))
                else if (video && thumbnail.isNotEmpty)
                  Image.file(File(thumbnail),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _placeholder(context))
                else
                  _placeholder(context),
                if (video)
                  const Center(
                      child: Icon(Icons.play_circle_fill_rounded,
                          size: AppTokens.profileAvatarSize,
                          color: AppTokens.onAccent)),
              ]),
            ),
    );
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
      color: CustomerServiceTokens.background(context),
      child: Icon(Icons.image_outlined,
          color: CustomerServiceTokens.secondaryText(context)));
}
