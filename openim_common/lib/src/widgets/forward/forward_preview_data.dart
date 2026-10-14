import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../chat/markdown/chat_message_text_source.dart';

enum ForwardPreviewKind {
  text,
  picture,
  video,
  file,
  voice,
  card,
  location,
  sticker,
  record,
  batch
}

/// Display-only snapshot. Never carries a playable video or audio source, and
/// never changes the messages subsequently validated by the sending controller.
class ForwardPreviewData {
  const ForwardPreviewData({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.imageUrl,
    this.imagePath,
    this.duration,
    this.lines = const [],
    this.count,
  });

  final ForwardPreviewKind kind;
  final String title, subtitle;
  final String? imageUrl, imagePath;
  final int? duration, count;
  final List<String> lines;

  factory ForwardPreviewData.fromMessages(List<Message> messages,
      {bool merged = false, String? mergeTitle}) {
    if (merged || messages.length > 1) {
      return ForwardPreviewData(
        kind: merged ? ForwardPreviewKind.record : ForwardPreviewKind.batch,
        title: merged
            ? (mergeTitle ?? StrRes.chatRecord)
            : 'forwardPreviewBatch'.tr,
        count: messages.length,
        lines: List.unmodifiable(messages.take(3).map((message) {
          final preview = ForwardPreviewData.fromMessage(message);
          final sender = message.senderNickname?.trim() ?? '';
          return '${merged && sender.isNotEmpty ? '$sender：' : ''}${preview.summary}';
        })),
      );
    }
    return messages.isEmpty
        ? ForwardPreviewData(
            kind: ForwardPreviewKind.text, title: StrRes.unsupportedMessage)
        : ForwardPreviewData.fromMessage(messages.single);
  }

  String get summary => switch (kind) {
        ForwardPreviewKind.text => title,
        ForwardPreviewKind.file => '[${StrRes.file}] $title',
        ForwardPreviewKind.card => '[${StrRes.carte}] $title',
        ForwardPreviewKind.location => '[${StrRes.toolboxLocation}] $title',
        ForwardPreviewKind.record => '[${StrRes.chatRecord}] $title',
        _ => '[$title]',
      };

  factory ForwardPreviewData.fromMessage(Message message) {
    switch (message.contentType) {
      case MessageType.text:
      case MessageType.atText:
      case MessageType.advancedText:
      case MessageType.quote:
        final quote = message.quoteElem?.quoteMessage;
        return ForwardPreviewData(
          kind: ForwardPreviewKind.text,
          title: chatMessageTextSource(message),
          // Use the bounded SDK summary, not recursive quote rendering.
          subtitle: quote == null
              ? ''
              : '${quote.senderNickname ?? ''}：${IMUtils.parseMsg(quote)}',
        );
      case MessageType.picture:
        final picture = message.pictureElem;
        return ForwardPreviewData(
            kind: ForwardPreviewKind.picture,
            title: StrRes.picture,
            imageUrl: _first([
              picture?.snapshotPicture?.url,
              picture?.bigPicture?.url,
              picture?.sourcePicture?.url
            ]),
            imagePath: picture?.sourcePath);
      case MessageType.video:
        return ForwardPreviewData(
            kind: ForwardPreviewKind.video,
            title: StrRes.video,
            imageUrl: message.videoElem?.snapshotUrl,
            imagePath: message.videoElem?.snapshotPath,
            duration: message.videoElem?.duration);
      case MessageType.voice:
        return ForwardPreviewData(
            kind: ForwardPreviewKind.voice,
            title: StrRes.voice,
            duration: message.soundElem?.duration);
      case MessageType.file:
        return ForwardPreviewData(
            kind: ForwardPreviewKind.file,
            title: _first([message.fileElem?.fileName]) ?? StrRes.file,
            subtitle: _fileSize(message.fileElem?.fileSize));
      case MessageType.card:
        return ForwardPreviewData(
            kind: ForwardPreviewKind.card,
            title: _first(
                    [message.cardElem?.nickname, message.cardElem?.userID]) ??
                StrRes.carte,
            subtitle: StrRes.carte,
            imageUrl: message.cardElem?.faceURL);
      case MessageType.location:
        final location = message.locationElem;
        final lat = location?.latitude, lng = location?.longitude;
        final valid = lat != null &&
            lng != null &&
            lat.isFinite &&
            lng.isFinite &&
            lat.abs() <= 90 &&
            lng.abs() <= 180;
        return ForwardPreviewData(
            kind: ForwardPreviewKind.location,
            title: _first([location?.description]) ?? StrRes.toolboxLocation,
            subtitle: valid
                ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                : StrRes.toolboxLocation);
      case MessageType.customFace:
        return ForwardPreviewData(
            kind: ForwardPreviewKind.sticker,
            title: StrRes.emoji,
            imageUrl: StickerImageData.tryParse(message.faceElem?.data)?.url);
      case MessageType.merger:
        return ForwardPreviewData(
            kind: ForwardPreviewKind.record,
            title: _first([message.mergeElem?.title]) ?? StrRes.chatRecord,
            lines: List.unmodifiable(
                (message.mergeElem?.abstractList ?? const <String>[]).take(3)),
            count: message.mergeElem?.multiMessage?.length);
      default:
        return ForwardPreviewData(
            kind: ForwardPreviewKind.text, title: IMUtils.parseMsg(message));
    }
  }

  static String? _first(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static String _fileSize(int? bytes) {
    if (bytes == null || bytes < 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
