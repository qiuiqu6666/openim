import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart' show MessageExt;

/// Read-only thumbnail projection for one real message on a calendar day.
class ChatDateDayImage {
  const ChatDateDayImage({
    required this.messageID,
    this.localPath,
    this.url,
  });

  final String messageID;
  final String? localPath;
  final String? url;

  static ChatDateDayImage? fromMessage(
    Message message, {
    required DateTime day,
    required bool Function(Message message) isRemoved,
  }) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final time = message.sendTime;
    final id = message.clientMsgID?.trim() ?? '';
    if (message.contentType != MessageType.picture ||
        id.isEmpty ||
        time == null ||
        time < start.millisecondsSinceEpoch ||
        time >= end.millisecondsSinceEpoch ||
        (message.status != null && message.status! > MessageStatus.failed) ||
        isRemoved(message) ||
        message.attachedInfoElem?.isPrivateChat == true ||
        message.hasExpired) {
      return null;
    }
    final picture = message.pictureElem;
    final localPath = _localPath(picture?.sourcePath);
    String? url;
    for (final candidate in [
      picture?.snapshotPicture?.url,
      picture?.bigPicture?.url,
      picture?.sourcePicture?.url,
    ]) {
      final value = candidate?.trim() ?? '';
      final uri = Uri.tryParse(value);
      if ((uri?.scheme == 'https' || uri?.scheme == 'http') &&
          uri!.host.isNotEmpty) {
        url = value;
        break;
      }
    }
    if (localPath == null && url == null) return null;
    return ChatDateDayImage(messageID: id, localPath: localPath, url: url);
  }

  static String? _localPath(String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty || value.contains('\u0000')) return null;
    // The existing thumbnail handles file existence asynchronously and falls
    // back to a remote snapshot; never read or download bytes in this model.
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.isEmpty) return value;
    if (uri.scheme != 'file') return null;
    try {
      final windows = uri.pathSegments.isNotEmpty &&
          RegExp(r'^[A-Za-z]:$').hasMatch(uri.pathSegments.first);
      return uri.toFilePath(windows: windows);
    } catch (_) {
      return null;
    }
  }
}
