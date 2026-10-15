import 'dart:convert';
import 'dart:io';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../preview/chat_top_picture_preview.dart';
import '../diagnostics/chat_media_diagnostics.dart';

/// Uses the existing authenticated OpenIM uploader. Only complete remote media
/// can enter SendMessageNotOss; clientMsgID and the normal delivery owner survive.
class ChatMediaUpload {
  ChatMediaUpload(
      {required this.isClosed,
      required this.onTransfer,
      this.previewTimeout = const Duration(seconds: 5),
      this.uploadTimeout = const Duration(minutes: 10),
      Future<ChatTopPicturePreview?> Function(String,
              {required bool Function() isCancelled})?
          createPreview})
      : _createPreview = createPreview ?? ChatTopPicturePreview.create;
  final bool Function() isClosed;
  final void Function(Message, ChatTransferStatus) onTransfer;
  final Duration previewTimeout, uploadTimeout;
  final Future<ChatTopPicturePreview?> Function(String,
      {required bool Function() isCancelled}) _createPreview;

  Future<String> _upload(
      String id, String path, String? contentType, ChatMediaTrace trace) async {
    if (isClosed()) throw StateError('Chat closed');
    final result = await trace.run(
        id.startsWith('chat-top-preview:') ? 'upload_preview' : 'upload_source',
        () => OpenIM.iMManager
            .uploadFile(
              id: id,
              filePath: path,
              fileName: path.split(Platform.pathSeparator).last,
              contentType: contentType,
              operationID: trace.id,
            )
            .timeout(uploadTimeout));
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

  Future<({PictureInfo picture, String? extra})?> _optionalPreview(
      Message message, String sourceURL, ChatMediaTrace trace) async {
    var expired = false;
    bool cancelled() => expired || isClosed();
    Future<({PictureInfo picture, String? extra})?> build() async {
      ChatTopPicturePreview? preview;
      try {
        preview = await _createPreview(message.pictureElem!.sourcePath!,
            isCancelled: cancelled);
        if (preview == null || cancelled()) return null;
        final url = await _upload('chat-top-preview:${message.clientMsgID}',
            preview.path, 'image/png', trace);
        if (cancelled()) return null;
        return (
          picture: PictureInfo(
              url: url,
              width: preview.width,
              height: preview.height,
              size: preview.length,
              type: 'image/png'),
          extra: ChatPicturePreviewMetadata.withTopCrop(message.ex,
              sourceURL: sourceURL, previewURL: url),
        );
      } finally {
        // A timeout does not cancel native IO. Dispose only after its reader
        // completes, and never let a late result mutate the submitted message.
        await preview?.dispose();
      }
    }

    try {
      return await build().timeout(previewTimeout);
    } catch (error) {
      trace.record('optional_preview',
          outcome: 'source_fallback', error: error);
      return null;
    } finally {
      expired = true;
    }
  }

  Future<void> prepare(Message message) async {
    onTransfer(
        message, const ChatTransferStatus(ChatTransferStage.uploading, 0));
    final id = message.clientMsgID!;
    final trace = ChatMediaTrace()..messageID = id;
    if (message.contentType == MessageType.picture) {
      final picture = message.pictureElem!;
      final source = picture.sourcePicture!;
      final url = await _upload(
          'chat-media:$id', picture.sourcePath!, source.type, trace);
      PictureInfo? topPreview;
      String? previewExtra;
      if ((source.width ?? 0) > 0 &&
          (source.height ?? 0) >
              source.width! * ChatPicturePreviewMetadata.heightRatio &&
          source.type?.toLowerCase() != 'image/gif' &&
          ChatPicturePreviewMetadata.canAnnotate(message.ex)) {
        final preview = await _optionalPreview(message, url, trace);
        topPreview = preview?.picture;
        previewExtra = preview?.extra;
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
      final snapshot = await _upload(
          'chat-snapshot:$id', video.snapshotPath!, 'image/jpeg', trace);
      final url = await _upload(
          'chat-media:$id', video.videoPath!, video.videoType, trace);
      // Commit both URLs together; a failed partial upload uses the SDK retry.
      video.snapshotUrl = snapshot;
      video.videoUrl = url;
    }
    if (!isClosed()) {
      onTransfer(message, const ChatTransferStatus(ChatTransferStage.queued));
    }
  }
}
