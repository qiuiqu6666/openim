import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../picture/chat_picture_quality.dart';
import 'chat_quote_tokens.dart';

class ChatQuoteThumbnail extends StatelessWidget {
  const ChatQuoteThumbnail({super.key, required this.message});
  final Message message;

  static bool supports(Message? message) =>
      message != null &&
      !message.hasExpired &&
      (message.isPictureType || message.isVideoType);

  @override
  Widget build(BuildContext context) {
    if (!supports(message)) return const SizedBox.shrink();
    final picture = message.pictureElem;
    final video = message.videoElem;
    final source = ChatPictureQuality.sourceSize(picture);
    final longPicture =
        message.isPictureType && source.height / source.width > 3;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final thumbnailPixels = (ChatQuoteTokens.thumbnailSize * pixelRatio).ceil();
    final decodeSize = longPicture
        ? ChatPictureQuality.decodeSize(
            source: source,
            displayWidth: ChatQuoteTokens.thumbnailSize,
            devicePixelRatio: pixelRatio)
        : Size(thumbnailPixels.toDouble(), thumbnailPixels.toDouble());
    final alignment = longPicture ? Alignment.topCenter : Alignment.center;
    final path =
        (message.isPictureType ? picture?.sourcePath : video?.snapshotPath)
            ?.trim();
    final thumbnailUrl = (message.isPictureType
            ? [
                picture?.snapshotPicture?.url,
                picture?.bigPicture?.url,
                picture?.sourcePicture?.url
              ]
            : [video?.snapshotUrl])
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .firstOrNull;
    final url = longPicture
        ? ChatPictureQuality.croppedSource(picture, decodeSize) ?? thumbnailUrl
        : thumbnailUrl;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = ColoredBox(
      color: AppTokens.surfaceAlt(dark: dark),
      child: Center(
          child: Icon(
        message.isVideoType ? Icons.videocam_outlined : Icons.image_outlined,
        color: AppTokens.textSecondary(dark: dark),
        size: AppTokens.s6,
      )),
    );
    Widget remote() => url == null
        ? placeholder
        : ImageUtil.networkImage(
            url: url,
            width: ChatQuoteTokens.thumbnailSize,
            height: ChatQuoteTokens.thumbnailSize,
            cacheWidth: decodeSize.width.toInt(),
            cacheHeight: decodeSize.height.toInt(),
            resizePolicy: ResizeImagePolicy.fit,
            fit: BoxFit.cover,
            alignment: alignment,
            loadProgress: false,
            loadingWidget: placeholder,
            errorWidget: placeholder,
          );
    return ExcludeSemantics(
        child: ClipRRect(
      borderRadius: BorderRadius.circular(ChatQuoteTokens.thumbnailRadius),
      child: SizedBox.square(
        dimension: ChatQuoteTokens.thumbnailSize,
        child: !kIsWeb && path?.isNotEmpty == true
            ? ImageUtil.fileImage(
                file: File(path!),
                width: ChatQuoteTokens.thumbnailSize,
                height: ChatQuoteTokens.thumbnailSize,
                cacheWidth: decodeSize.width.toInt(),
                cacheHeight: decodeSize.height.toInt(),
                resizePolicy: ResizeImagePolicy.fit,
                fit: BoxFit.cover,
                alignment: alignment,
                loadProgress: false,
                errorWidget: remote(),
              )
            : remote(),
      ),
    ));
  }
}
