import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import 'chat_builtin_sticker.dart';
import 'chat_builtin_sticker_image_cache.dart';

typedef BuiltinStickerUpload = Future<Object?> Function({
  required String id,
  required String filePath,
  required String fileName,
});

/// Uploads bundled bytes before creating an ordinary URL-based SDK face message.
/// The same delivery owner still owns destination, drafts and send receipts.
class ChatBuiltinStickerSender {
  ChatBuiltinStickerSender({
    required bool Function() isClosed,
    required bool Function() sendingMuted,
    required bool Function() isInvalidGroup,
    required Future Function(Message) sendMessage,
    AssetBundle? bundle,
    Future<Directory> Function()? cacheDirectory,
    BuiltinStickerUpload? upload,
    Future<Message> Function(String data)? createFace,
    Future<void> Function({required String url, required Uint8List bytes})?
        warmImage,
    Object? Function()? sessionKey,
  })  : _isClosed = isClosed,
        _sendingMuted = sendingMuted,
        _isInvalidGroup = isInvalidGroup,
        _sendMessage = sendMessage,
        _bundle = bundle ?? rootBundle,
        _cacheDirectory = cacheDirectory ?? _defaultDirectory,
        _upload = upload ?? _uploadFile,
        _createFace = createFace ?? _createFaceMessage,
        _warmImage = warmImage,
        _sessionKey = sessionKey ?? _readSession {
    _owner = _sessionKey();
  }

  final bool Function() _isClosed, _sendingMuted, _isInvalidGroup;
  final Future Function(Message) _sendMessage;
  final AssetBundle _bundle;
  final Future<Directory> Function() _cacheDirectory;
  final BuiltinStickerUpload _upload;
  final Future<Message> Function(String) _createFace;
  final Future<void> Function({required String url, required Uint8List bytes})?
      _warmImage;
  final Object? Function() _sessionKey;
  late final Object? _owner;
  final _sending = <String, Future<void>>{};
  bool _closed = false;

  bool get _current =>
      !_closed &&
      !_isClosed() &&
      _owner != null &&
      _owner == _sessionKey() &&
      !_sendingMuted() &&
      !_isInvalidGroup();

  static Object? _readSession() {
    final userID = OpenIM.iMManager.userID;
    if (userID.isEmpty) return null;
    return (
      userID,
      OpenIM.iMManager.token,
      DataSp.chatToken,
      DataSp.imToken,
      Config.appAuthUrl,
    );
  }

  static Future<Directory> _defaultDirectory() async =>
      Directory('${Config.cachePath}/outgoing_stickers');

  static Future<Object?> _uploadFile({
    required String id,
    required String filePath,
    required String fileName,
  }) =>
      OpenIM.iMManager.uploadFile(
          id: id,
          filePath: filePath,
          fileName: fileName,
          contentType: 'image/png');

  static Future<Message> _createFaceMessage(String data) =>
      OpenIM.iMManager.messageManager.createFaceMessage(index: -1, data: data);

  Future<void> send(ChatBuiltinSticker sticker) {
    if (!_current) return Future.value();
    final registered = ChatBuiltinStickerCatalog.byID(sticker.id);
    if (registered == null ||
        registered.assetPath != sticker.assetPath ||
        registered.fileName != sticker.fileName ||
        registered.width != sticker.width ||
        registered.height != sticker.height) {
      return Future.error(const FormatException('表情资源不可用'));
    }
    final existing = _sending[sticker.id];
    if (existing != null) return existing;
    late final Future<void> work;
    work = _send(registered).whenComplete(() {
      if (identical(_sending[registered.id], work)) {
        _sending.remove(registered.id);
      }
    });
    return _sending[registered.id] = work;
  }

  Future<void> _send(ChatBuiltinSticker sticker) async {
    File? file;
    try {
      final bytes = await _bundle.load(sticker.assetPath);
      if (!_current) return;
      if (bytes.lengthInBytes == 0 || bytes.lengthInBytes > 10 * 1024 * 1024) {
        throw const FormatException('表情资源不可用');
      }
      final directory = await _cacheDirectory();
      if (!_current) return;
      await directory.create(recursive: true);
      if (!_current) return;
      file = File('${directory.path}/${const Uuid().v4()}-${sticker.fileName}');
      await file.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true);
      if (!_current) return;
      final result = await _upload(
          id: const Uuid().v4(),
          filePath: file.path,
          fileName: sticker.fileName);
      if (!_current) return;
      final url = _uploadURL(result);
      if (!_current) return;
      try {
        final imageBytes =
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
        final warmImage = _warmImage;
        if (warmImage != null) {
          await warmImage(url: url, bytes: imageBytes);
        } else {
          await warmBuiltinStickerImage(
              url: url, bytes: imageBytes, isCurrent: () => _current);
        }
      } catch (_) {
        // Cache warm-up is optional; the ordinary URL image remains usable.
      }
      if (!_current) return;
      final message = await _createFace(StickerImageData(
              url: url, width: sticker.width, height: sticker.height)
          .encode());
      if (!_current) return;
      await _sendMessage(message);
    } catch (_) {
      if (_current) throw const FormatException('表情发送失败，请重试');
    } finally {
      if (file != null) {
        try {
          await file.delete();
        } catch (_) {
          // Cleanup cannot change a successful send or report on another chat.
        }
      }
    }
  }

  static String _uploadURL(Object? result) {
    final response = result is String ? jsonDecode(result) : result;
    final value = response is Map ? response['url'] : null;
    final url = value is String ? value.trim() : '';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('表情上传未返回可用地址');
    }
    return url;
  }

  void close() {
    _closed = true;
  }
}
