import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

typedef MediaMessageSender = Future Function(Message message,
    {bool addToUI, bool resetInput});

/// Owns attachment selection and preparation for one chat session.
class ChatMediaController {
  ChatMediaController({
    required String Function() conversationID,
    required bool Function() isClosed,
    required bool Function() sendingMuted,
    required bool Function() isInvalidGroup,
    required bool Function() voiceBusy,
    required MediaMessageSender sendMessage,
    required void Function(Message) stageMessage,
    required Future<void> Function(File, int) previewVoice,
    required this.closeToolbox,
  })  : _conversationID = conversationID,
        _isClosed = isClosed,
        _sendingMuted = sendingMuted,
        _isInvalidGroup = isInvalidGroup,
        _voiceBusy = voiceBusy,
        _sendMessage = sendMessage,
        _stageMessage = stageMessage,
        _previewAndSendVoice = previewVoice;

  final String Function() _conversationID;
  final bool Function() _isClosed, _sendingMuted, _isInvalidGroup, _voiceBusy;
  final MediaMessageSender _sendMessage;
  final void Function(Message) _stageMessage;
  final Future<void> Function(File, int) _previewAndSendVoice;
  final void Function() closeToolbox;
  final tempMessages = <Message>[];
  bool _closed = false;
  bool get isClosed => _closed || _isClosed();
  bool get sendingMuted => _sendingMuted();
  bool get isInvalidGroup => _isInvalidGroup();
  bool get pickingAttachment => _pickingAttachment;

  void close() {
    _closed = true;
    tempMessages.clear();
  }

  Future<List<Message>> searchMediaMessage() async {
    final messageList = await OpenIM.iMManager.messageManager
        .searchLocalMessages(
            conversationID: _conversationID(),
            messageTypeList: [MessageType.picture, MessageType.video],
            count: 500);
    return messageList.searchResultItems?.first.messageList?.reversed
            .toList() ??
        [];
  }

  Future sendPicture({required String path, bool sendNow = true}) async {
    if (isClosed) return;
    final file = await IMUtils.compressImageAndGetFile(File(path));
    if (isClosed) return;

    var message =
        await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
      imagePath: file!.path,
    );

    if (isClosed) return;

    if (sendNow) {
      return _sendMessage(message);
    } else {
      _stageMessage(message);
      tempMessages.add(message);
    }
  }

  Future<void> onTapLocation() async {
    if (isClosed) return;
    closeToolbox();
    final point =
        await Get.to<({double latitude, double longitude, String description})>(
            () => const ChatLocationPicker());
    if (point == null || isClosed) return;
    try {
      final message = await OpenIM.iMManager.messageManager
          .createLocationMessage(
              latitude: point.latitude,
              longitude: point.longitude,
              description: point.description.isEmpty
                  ? StrRes.location
                  : point.description);
      if (!isClosed) await _sendMessage(message);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  Future<void> onTapAlbum() async {
    if (isClosed ||
        sendingMuted ||
        isInvalidGroup ||
        _pickingAttachment ||
        _voiceBusy()) {
      return;
    }
    _pickingAttachment = true;
    try {
      final List<AssetEntity>? assets = await AssetPicker.pickAssets(
          Get.context!,
          pickerConfig: AssetPickerConfig(
              requestType: RequestType.common,
              sortPathsByModifiedDate: true,
              filterOptions: PMFilter.defaultValue(containsPathModified: true),
              selectPredicate: (_, entity, isSelected) async {
                if (entity.type == AssetType.image) {
                  if (await allowSendImageType(entity)) {
                    return true;
                  }

                  IMViews.showToast(StrRes.supportsTypeHint);

                  return false;
                }

                if (entity.videoDuration > const Duration(seconds: 5 * 60)) {
                  IMViews.showToast(
                      sprintf(StrRes.selectVideoLimit, [5]) + StrRes.minute);
                  return false;
                }
                return true;
              }));
      if (null != assets && !isClosed) {
        for (var asset in assets) {
          try {
            await _handleAssets(asset, sendNow: false);
          } catch (_) {
            IMViews.showToast(StrRes.sendFailed);
          }
        }

        for (final msg in List<Message>.of(tempMessages)) {
          if (isClosed) break;
          await _sendMessage(msg, addToUI: false);
        }

        tempMessages.clear();
      }
    } finally {
      _pickingAttachment = false;
    }
  }

  bool _pickingAttachment = false;
  Future<File> _retainAttachment(String path) async {
    final name = path.split(Platform.pathSeparator).last;
    final directory = Directory('${Config.cachePath}/outgoing_media');
    await directory.create(recursive: true);
    return File(path).copy(
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$name');
  }

  Future<void> onTapFile() => _pickAttachment(false);
  Future<void> onTapCamera() async {
    if (_pickingAttachment || _voiceBusy() || isClosed) return;
    _pickingAttachment = true;
    try {
      final asset = await CameraPicker.pickFromCamera(Get.context!,
          pickerConfig: const CameraPickerConfig(
              enableRecording: true,
              enableAudio: true,
              maximumRecordingDuration: Duration(seconds: 60)));
      if (asset != null && !isClosed) await _handleAssets(asset);
    } catch (_) {
      IMViews.showToast(StrRes.sendFailed);
    } finally {
      _pickingAttachment = false;
    }
  }

  Future<void> onTapAudio() => _pickAttachment(true);
  Future<void> _pickAttachment(bool isAudio) async {
    if (_pickingAttachment ||
        _voiceBusy() ||
        isClosed ||
        sendingMuted ||
        isInvalidGroup) {
      return;
    }
    _pickingAttachment = true;
    final accountID = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    File? unclaimedAudio;
    try {
      final result = await FilePicker.platform
          .pickFiles(type: isAudio ? FileType.audio : FileType.any);
      if (result == null ||
          isClosed ||
          accountID != OpenIM.iMManager.userID ||
          token != DataSp.chatToken) {
        return;
      }
      final selected = result.files.single;
      if (selected.path == null) throw StateError('File unavailable');
      final file = await _retainAttachment(selected.path!);
      if (isAudio) unclaimedAudio = file;
      if (isClosed) return;
      Message message;
      if (isAudio) {
        final player = audio.AudioPlayer();
        late int seconds;
        try {
          final duration = await player.setFilePath(file.path);
          if (duration == null || duration.inMilliseconds <= 0) {
            throw StateError('Invalid audio');
          }
          seconds = (duration.inMilliseconds / 1000).ceil();
        } finally {
          await player.dispose();
        }
        if (isClosed) return;
        unclaimedAudio = null; // The preview now owns disposal or retention.
        await _previewAndSendVoice(file, seconds);
        return;
      } else {
        message = await OpenIM.iMManager.messageManager
            .createFileMessageFromFullPath(
                filePath: file.path, fileName: selected.name);
      }
      if (!isClosed) await _sendMessage(message);
    } catch (_) {
      IMViews.showToast(StrRes.sendFailed);
    } finally {
      if (unclaimedAudio != null) {
        try {
          if (await unclaimedAudio.exists()) await unclaimedAudio.delete();
        } catch (_) {}
      }
      _pickingAttachment = false;
    }
  }

  Future<bool> allowSendImageType(AssetEntity entity) async {
    final mimeType = await entity.mimeTypeAsync;

    return IMUtils.allowImageType(mimeType);
  }

  Future _handleAssets(AssetEntity? asset, {bool sendNow = true}) async {
    if (null != asset) {
      Logger.print(
          '--------assets type-----${asset.type} create time: ${asset.createDateTime}');
      final originalFile = await asset.file;
      if (originalFile == null) {
        IMViews.showToast(StrRes.sendFailed);
        return;
      }
      if (isClosed) return;
      final originalPath = originalFile.path;
      var path = originalPath.toLowerCase().endsWith('.gif')
          ? originalPath
          : originalFile.path;
      Logger.print('--------assets path-----$path');
      switch (asset.type) {
        case AssetType.image:
          await sendPicture(path: path, sendNow: sendNow);
          break;
        case AssetType.video:
          final saved = await _retainAttachment(path);
          if (isClosed) return;
          final thumbnail =
              await asset.thumbnailDataWithSize(const ThumbnailSize(640, 640));
          if (isClosed) return;
          if (thumbnail == null) {
            throw StateError('Video thumbnail unavailable');
          }
          final snapshot = File('${saved.path}.jpg');
          await snapshot.writeAsBytes(thumbnail);
          final mimeType = await asset.mimeTypeAsync ?? 'video/mp4';
          if (isClosed) return;
          final message = await OpenIM.iMManager.messageManager
              .createVideoMessageFromFullPath(
                  videoPath: saved.path,
                  videoType: mimeType,
                  duration: asset.videoDuration.inSeconds < 1
                      ? 1
                      : asset.videoDuration.inSeconds,
                  snapshotPath: snapshot.path);
          if (isClosed) return;
          if (sendNow) {
            await _sendMessage(message);
          } else {
            _stageMessage(message);
            tempMessages.add(message);
          }
          break;
        default:
          break;
      }
    }
  }
}
