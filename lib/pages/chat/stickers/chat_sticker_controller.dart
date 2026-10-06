import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import 'builtin/chat_builtin_sticker.dart';
import 'builtin/chat_builtin_sticker_sender.dart';
import 'dice/chat_dice_sender.dart';
import 'personal_sticker_store.dart';
import 'sticker_video_message.dart';

/// Owns personal sticker collection retries and sticker delivery.
class ChatStickerController {
  ChatStickerController({
    required bool Function() isClosed,
    required bool Function() sendingMuted,
    required bool Function() isInvalidGroup,
    required Future Function(Message) sendMessage,
    Future Function(Message)? sendBuiltinMessage,
    required this.closeToolbox,
  })  : _isClosed = isClosed,
        _sendingMuted = sendingMuted,
        _isInvalidGroup = isInvalidGroup,
        _sendMessage = sendMessage,
        _sendBuiltinMessage = sendBuiltinMessage ?? sendMessage;

  final bool Function() _isClosed, _sendingMuted, _isInvalidGroup;
  final Future Function(Message) _sendMessage;
  final Future Function(Message) _sendBuiltinMessage;
  ChatBuiltinStickerSender? _builtin;
  ChatDiceSender? _dice;
  final void Function() closeToolbox;
  final personalStickers = PersonalStickerStore();
  ({String url, String requestID})? _pendingSticker;
  bool _closed = false;
  bool get isClosed => _closed || _isClosed();
  bool get sendingMuted => _sendingMuted();
  bool get isInvalidGroup => _isInvalidGroup();

  static String? messageStickerURL(Message message) {
    if (message.status != MessageStatus.succeeded ||
        message.attachedInfoElem?.isPrivateChat == true ||
        (message.attachedInfoElem?.burnDuration ?? 0) > 0) {
      return null;
    }
    if (message.attachedInfo?.isNotEmpty == true) {
      try {
        final info = jsonDecode(message.attachedInfo!);
        if (info is! Map ||
            info['isPrivateChat'] == true ||
            (info['burnDuration'] is num && info['burnDuration'] > 0)) {
          return null;
        }
      } catch (_) {
        return null;
      }
    }
    final data = message.contentType == MessageType.customFace
        ? message.faceElem?.data
        : message.isEmojiType
            ? message.customElem?.data
            : isStickerVideoMessage(message)
                ? message.videoElem?.videoUrl
                : null;
    return StickerImageData.tryParse(data)?.url;
  }

  final Map<String, String> _messageStickerRequests = {};
  bool _addingMessageSticker = false;

  Future<void> addMessageToStickers(Message message) async {
    final url = messageStickerURL(message);
    if (isClosed || url == null || _addingMessageSticker) return;
    final account = DataSp.userID;
    final token = DataSp.chatToken;
    final key = '$account:$token:$url';
    final requestID =
        _messageStickerRequests.putIfAbsent(key, () => const Uuid().v4());
    _addingMessageSticker = true;
    try {
      await personalStickers.add(url, requestID);
      if (!isClosed && account == DataSp.userID && token == DataSp.chatToken) {
        IMViews.showToast('已添加到表情');
      }
    } catch (e) {
      if (!isClosed && account == DataSp.userID && token == DataSp.chatToken) {
        IMViews.showToast(
            e is StickerApiException ? '添加失败：${e.message}' : '添加失败，请重试');
      }
    } finally {
      _addingMessageSticker = false;
    }
  }

  void close() {
    _closed = true;
    _builtin?.close();
    _dice?.close();
    personalStickers.dispose();
  }

  Future<void> sendBuiltinSticker(ChatBuiltinSticker sticker) {
    if (isClosed || sendingMuted || isInvalidGroup) return Future.value();
    return (_builtin ??= ChatBuiltinStickerSender(
      isClosed: () => isClosed,
      sendingMuted: () => sendingMuted,
      isInvalidGroup: () => isInvalidGroup,
      sendMessage: _sendBuiltinMessage,
    ))
        .send(sticker);
  }

  Future<void> sendDice() {
    if (isClosed || sendingMuted || isInvalidGroup) return Future.value();
    return (_dice ??= ChatDiceSender(
      isClosed: () => isClosed,
      sendingMuted: () => sendingMuted,
      isInvalidGroup: () => isInvalidGroup,
      sendMessage: _sendBuiltinMessage,
    ))
        .send();
  }

  Future<void> onTapEmoji() async {
    if (isClosed) return;
    closeToolbox();
    try {
      final files = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'gif', 'webp', 'jpg']);
      final file = files?.files.first;
      if (file?.path == null || isClosed) return;
      if (file!.size > 10 * 1024 * 1024) {
        IMViews.showToast('sdkEmojiTooLarge'.tr);
        return;
      }
      final accepted =
          await Get.dialog<bool>(CustomDialog(title: 'sdkSendEmojiConfirm'.tr));
      if (accepted != true || isClosed) return;
      final result = await LoadingView.singleton.wrap(
          asyncFunction: () => OpenIM.iMManager.uploadFile(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              filePath: file.path!,
              fileName: file.name));
      if (isClosed) return;
      final data = result is String ? jsonDecode(result) : result;
      final url = data['url'] as String;
      final message = await OpenIM.iMManager.messageManager
          .createFaceMessage(index: -1, data: url);
      if (!isClosed) await _sendMessage(message);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future<void> addPersonalSticker() async {
    if (isClosed) return;
    try {
      var pending = _pendingSticker;
      if (pending != null) {
        final retry = await Get.dialog<bool>(AlertDialog(
          title: const Text('上次收藏未完成'),
          content: const Text('重试上次收藏，或选择新的文件？'),
          actions: [
            TextButton(
                onPressed: () => Get.back(result: false),
                child: const Text('选择新文件')),
            TextButton(
                onPressed: () => Get.back(result: true),
                child: const Text('重试')),
          ],
        ));
        if (retry == null || isClosed) return;
        if (!retry) {
          _pendingSticker = null;
          pending = null;
        }
      }
      if (pending == null) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'mp4'],
        );
        final file = picked?.files.single;
        if (file?.path == null || isClosed) return;
        final maxSize = file!.extension?.toLowerCase() == 'mp4'
            ? 20 * 1024 * 1024
            : 10 * 1024 * 1024;
        if (file.size > maxSize) {
          IMViews.showToast('文件超过表情收藏上限');
          return;
        }
        final result = await LoadingView.singleton.wrap(
          asyncFunction: () => OpenIM.iMManager.uploadFile(
            id: const Uuid().v4(),
            filePath: file.path!,
            fileName: file.name,
          ),
        );
        if (isClosed) return;
        final data = result is String ? jsonDecode(result) : result;
        final url = data['url'] as String?;
        if (url == null || url.isEmpty) throw StateError('上传未返回文件地址');
        pending = (url: url, requestID: const Uuid().v4());
        _pendingSticker = pending;
      }
      await personalStickers.add(pending.url, pending.requestID);
      _pendingSticker = null;
    } on StickerApiException catch (error) {
      if ([1001, 20012, 20021, 20022, 20023].contains(error.code)) {
        _pendingSticker = null;
      }
      IMViews.showToast('收藏失败：$error');
    } catch (error) {
      IMViews.showToast('收藏失败：$error');
    }
  }

  Future<void> sendPersonalSticker(PersonalSticker sticker) async {
    if (isClosed || sendingMuted || isInvalidGroup) return;
    if (!sticker.isVideo) {
      final data = StickerImageData(
        url: sticker.mediaURL,
        width: sticker.width,
        height: sticker.height,
      ).encode();
      final message = await OpenIM.iMManager.messageManager
          .createFaceMessage(index: -1, data: data);
      if (!isClosed) await _sendMessage(message);
      return;
    }
    final directory = Directory('${Config.cachePath}/outgoing_media');
    await directory.create(recursive: true);
    if (isClosed) return;
    final prefix = const Uuid().v4();
    final video = File('${directory.path}/$prefix.mp4');
    final cover = File('${directory.path}/$prefix.jpg');
    await dio.download(sticker.mediaURL, video.path);
    if (isClosed) return;
    await dio.download(sticker.thumbnailURL!, cover.path);
    if (isClosed) return;
    final message =
        await OpenIM.iMManager.messageManager.createVideoMessageFromFullPath(
      videoPath: video.path,
      videoType: sticker.mimeType,
      duration: ((sticker.durationMs ?? 1000) / 1000).ceil(),
      snapshotPath: cover.path,
    );
    if (isClosed) return;
    markStickerVideoMessage(message);
    await _sendMessage(message);
  }
}
