import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/localization.dart';

import '../../../services/favorite_api.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import '../data/favorite_media_upload.dart';

/// Presentation for the existing favorite upload contract. No server error
/// payloads, signed URLs or local file paths are shown to the user.
abstract final class FavoriteMediaFeedback {
  static String limitHint(BuildContext context, FavoriteKind kind) {
    final size = FavoriteMediaUploader.maxSizeBytes(kind) ~/ (1024 * 1024);
    return settingsText(context,
        zh: kind == FavoriteKind.video
            ? AppCopy.format('每个不超过 {#0} MiB；MP4（H.264 视频／AAC 音频）', [size],
                locale: Localizations.localeOf(context))
            : kind == FavoriteKind.image
                ? AppCopy.format('每张不超过 {#0} MiB；JPEG、PNG、GIF、WebP', [size],
                    locale: Localizations.localeOf(context))
                : AppCopy.format('每个不超过 {#0} MiB', [size],
                    locale: Localizations.localeOf(context)),
        en: kind == FavoriteKind.video
            ? 'Up to $size MiB each; MP4 with H.264 video / AAC audio'
            : kind == FavoriteKind.image
                ? 'Up to $size MiB each; JPEG, PNG, GIF, WebP'
                : 'Up to $size MiB each');
  }

  static String failureMessage(BuildContext context, Object error,
      {required FavoriteKind kind}) {
    String text(String zh, String en) => settingsText(context, zh: zh, en: en);
    final code = error is FavoriteApiException ? error.code.toString() : '';
    if (code == '20058' || code == 'MEDIA_TOO_LARGE') {
      return '${limitHint(context, kind)}\n${kind == FavoriteKind.video ? text('视频时长还需在 24 小时以内。请裁剪或压缩后再收藏。', 'Videos must also be no longer than 24 hours. Trim or compress the video before saving again.') : text('请选择较小的原文件后再收藏。', 'Choose a smaller original file before saving again.')}';
    }
    if (code == '20059' || code == 'UNSUPPORTED_MEDIA') {
      return kind == FavoriteKind.video
          ? text(
              '视频未通过格式校验或封面处理。请转换为 MP4（H.264 视频／AAC 音频）后重新选择；若已符合格式要求，可裁剪或压缩后再试。',
              'The video could not be validated or its cover generated. Convert it to MP4 with H.264 video / AAC audio, then select it again. If it already uses this format, try trimming or compressing it.')
          : kind == FavoriteKind.image
              ? text('图片格式或内容不支持，请转换为 JPEG 或 PNG 后重新选择。',
                  'This image format or content is not supported. Convert it to JPEG or PNG and select it again.')
              : text('文件格式或内容不支持，请选择能正常打开的原文件后重试。',
                  'This file format or content is not supported. Select an original file that opens correctly and try again.');
    }
    if (code == '20060') {
      return text('收藏容量或条数已达上限，请删除不需要的收藏后重试。',
          'Your favorites storage or item limit has been reached. Remove unwanted favorites and try again.');
    }
    if (code == '20065') {
      return text('收藏操作过于频繁，请稍等一分钟后再试。',
          'Too many favorite operations. Wait a minute and try again.');
    }
    if (code == '20056' ||
        code == 'ORIGINAL_UNAVAILABLE' ||
        code == 'UPLOAD_EXPIRED' ||
        error is FileSystemException) {
      return text('原文件不可读取或上传授权已过期，请重新选择原文件后再试。',
          'The original file is unavailable or the upload authorization expired. Select the original file again.');
    }
    if (error is FavoriteApiException && error.isAuthError) {
      return text('登录已失效，请重新登录后再收藏。',
          'Your session has expired. Sign in again before saving.');
    }
    if (code == 'UPLOAD_FAILED' ||
        error is DioException ||
        error is TimeoutException ||
        error is SocketException) {
      return text('上传未完成，可能是网络中断或上传服务暂不可用。请检查网络后重试。',
          'The upload did not finish. The connection may have dropped or the upload service may be unavailable. Check your connection and retry.');
    }
    if (error is FavoriteApiException && error.isUncertain) {
      return text('暂时无法确认是否收藏成功。请先刷新收藏列表查看结果，避免重复添加。',
          'The save result is not confirmed. Refresh your favorites to check before adding it again.');
    }
    if (code == 'NETWORK_ERROR' || code == 'HTTP_ERROR') {
      return text('暂时无法连接收藏服务，请检查网络后重试。',
          'Cannot reach the favorites service. Check your connection and retry.');
    }
    if (code == '20066') {
      return text('收藏服务暂时不可用，请稍后重试。',
          'Favorites are temporarily unavailable. Try again later.');
    }
    return text('收藏未完成，请刷新列表确认结果后重试；若持续失败，请上传日志并反馈。',
        'Saving did not finish. Refresh the list to check the result before retrying. If it keeps failing, upload logs and send feedback.');
  }

  static Future<void> showFailure(BuildContext context, Object error,
      {required FavoriteKind kind}) async {
    if (error is FavoriteApiException && error.isCancelled) return;
    await showAppAlert<void>(context,
        title:
            settingsText(context, zh: '未能完成收藏', en: 'Could not save favorite'),
        message: failureMessage(context, error, kind: kind),
        actions: [
          AppAction(settingsText(context, zh: '知道了', en: 'OK'), null),
        ]);
  }
}
