import 'dart:convert';
import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../preview/chat_top_picture_preview.dart';

/// Uses the existing authenticated OpenIM uploader. Only complete remote media
/// can enter SendMessageNotOss; clientMsgID and the normal delivery owner survive.
class ChatMediaUpload {
  ChatMediaUpload({required this.isClosed, required this.onTransfer});
  final bool Function() isClosed;
  final void Function(Message, ChatTransferStatus) onTransfer;

  Future<String> _upload(String id, String path, String? contentType) async {
    if (isClosed()) throw StateError('Chat closed');
    final result = await OpenIM.iMManager
        .uploadFile(
          id: id,
          filePath: path,
          fileName: path.split(Platform.pathSeparator).last,
          contentType: contentType,
        )
        .timeout(const Duration(minutes: 10));
    if (isClosed()) throw StateError('Chat closed');
    final decoded = result is String ? jsonDecode(result) : result;
    final url = decoded is Map ? decoded['url'] : null;
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('Upload did not return a media URL');
    }
    return url as String;
  }

  Future<void> prepare(Message message) async {
    onTransfer(
        message, const ChatTransferStatus(ChatTransferStage.uploading, 0));
    final id = message.clientMsgID!;
    if (message.contentType == MessageType.picture) {
      final picture = message.pictureElem!;
      final source = picture.sourcePicture!;
      final url =
          await _upload('chat-media:$id', picture.sourcePath!, source.type);
      PictureInfo? topPreview;
      String? previewExtra;
      if ((source.width ?? 0) > 0 &&
          (source.height ?? 0) >
              source.width! * ChatPicturePreviewMetadata.heightRatio &&
          source.type?.toLowerCase() != 'image/gif' &&
          ChatPicturePreviewMetadata.canAnnotate(message.ex)) {
        ChatTopPicturePreview? preview;
        try {
          preview = await ChatTopPicturePreview.create(picture.sourcePath!,
              isCancelled: isClosed);
          if (preview != null && !isClosed()) {
            final previewURL = await _upload(
                'chat-top-preview:$id', preview.path, 'image/png');
            topPreview = PictureInfo(
                url: previewURL,
                width: preview.width,
                height: preview.height,
                size: preview.length,
                type: 'image/png');
            previewExtra = ChatPicturePreviewMetadata.withTopCrop(message.ex,
                sourceURL: url, previewURL: previewURL);
          }
        } catch (_) {
          // Keep the original send working if the optional derivative fails.
        } finally {
          await preview?.dispose();
        }
      }
      if (isClosed()) throw StateError('Chat closed');
      source.url = url;
      picture.bigPicture = PictureInfo.fromJson(source.toJson());
      picture.snapshotPicture = topPreview ??
          (PictureInfo.fromJson(source.toJson())
            ..url = OpenIMMediaUrl.thumbnail(url, width: 640, height: 640));
      if (previewExtra != null) message.ex = previewExtra;
    } else if (message.contentType == MessageType.video) {
      final video = message.videoElem!;
      final snapshot =
          await _upload('chat-snapshot:$id', video.snapshotPath!, 'image/jpeg');
      final url =
          await _upload('chat-media:$id', video.videoPath!, video.videoType);
      // Commit both URLs together; a failed partial upload uses the SDK retry.
      video.snapshotUrl = snapshot;
      video.videoUrl = url;
    }
    if (!isClosed()) {
      onTransfer(message, const ChatTransferStatus(ChatTransferStage.queued));
    }
  }
}
