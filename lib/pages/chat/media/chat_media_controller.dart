import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as p;
import 'package:sprintf/sprintf.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import 'upload/ordered_media_batch.dart';
import 'upload/chat_media_upload.dart';
import 'video/chat_video_preparation.dart';

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
    this.onTransfer,
    this.onUploadFailed,
    Future<List<AssetEntity>?> Function()? pickAssets,
    Future<File?> Function(File)? compressImage,
    void Function()? onPreparationFailed,
  })  : _conversationID = conversationID,
        _isClosed = isClosed,
        _sendingMuted = sendingMuted,
        _isInvalidGroup = isInvalidGroup,
        _voiceBusy = voiceBusy,
        _sendMessage = sendMessage,
        _stageMessage = stageMessage,
        _previewAndSendVoice = previewVoice,
        _pickAssets = pickAssets,
        _compressImage = compressImage ?? IMUtils.compressImageAndGetFile,
        _onPreparationFailed =
            onPreparationFailed ?? (() => IMViews.showToast(StrRes.sendFailed));

  final String Function() _conversationID;
  final bool Function() _isClosed, _sendingMuted, _isInvalidGroup, _voiceBusy;
  final MediaMessageSender _sendMessage;
  final void Function(Message) _stageMessage;
  final Future<void> Function(File, int) _previewAndSendVoice;
  final void Function() closeToolbox;
  final void Function(Message, ChatTransferStatus)? onTransfer;
  final void Function(Message)? onUploadFailed;
  final Future<List<AssetEntity>?> Function()? _pickAssets;
  final Future<File?> Function(File) _compressImage;
  final void Function() _onPreparationFailed;
  final tempMessages = <Message>[];
  final preparingCount = 0.obs;
  bool _closed = false;
  bool get isClosed => _closed || _isClosed();
  bool get sendingMuted => _sendingMuted();
  bool get isInvalidGroup => _isInvalidGroup();
  bool get pickingAttachment => _pickingAttachment;

  void close() {
    _closed = true;
    tempMessages.clear();
    preparingCount.value = 0;
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
    final message = await _preparePicture(path);
    if (message == null || isClosed) return;
    if (sendNow) {
      return _sendMessage(message);
    } else {
      _stageMessage(message);
      tempMessages.add(message);
    }
  }

  Future<Message?> _preparePicture(String path) async {
    if (isClosed) return null;
    // Keep the source and compression target unique while earlier photos upload.
    final original = await _retainAttachment(path);
    if (isClosed) return null;
    if (await original.length() == 0) {
      throw StateError('Image file is empty');
    }
    var file = original;
    try {
      final compressed = await _compressImage(original);
      if (isClosed) return null;
      if (compressed != null &&
          await compressed.exists() &&
          await compressed.length() > 0) {
        file = compressed;
      }
    } catch (_) {
      // Compression is optional. A readable local source can still be sent.
      Logger.print('Image compression failed; using retained source',
          onlyConsole: true);
    }
    if (isClosed) return null;
    final message =
        await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
      imagePath: file.path,
    );
    if (isClosed) return null;
    return message;
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
      final assets = await (_pickAssets?.call() ?? _selectAlbumAssets());
      if (assets != null && assets.isNotEmpty && !isClosed) {
        closeToolbox();
        await _sendSelectedAssets(assets);
      }
    } catch (_) {
      if (!isClosed) _onPreparationFailed();
    } finally {
      _pickingAttachment = false;
    }
  }

  Future<List<AssetEntity>?> _selectAlbumAssets() =>
      AssetPicker.pickAssets(Get.context!,
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

                if (entity.videoDuration > const Duration(minutes: 30)) {
                  IMViews.showToast(
                      sprintf(StrRes.selectVideoLimit, [30]) + StrRes.minute);
                  return false;
                }
                return true;
              }));

  Future<void> _sendSelectedAssets(List<AssetEntity> assets) async {
    final quality = assets.any((asset) => asset.type == AssetType.video)
        ? await chooseChatVideoQuality()
        : ChatVideoQuality.original;
    if (quality == null || isClosed) return;
    final ready = List.generate(assets.length, (_) => Completer<Message?>());
    final messages = <int, Message>{};
    preparingCount.value = assets.length;
    Future<void> prepareLocal() async {
      try {
        for (var index = 0; index < assets.length; index++) {
          Message? message;
          try {
            if (!isClosed) {
              message = await _prepareAsset(assets[index], quality: quality);
              if (message != null && !isClosed) {
                messages[index] = message;
                _stageMessage(message);
                onTransfer?.call(message,
                    const ChatTransferStatus(ChatTransferStage.queued));
              }
            }
          } catch (_) {
            if (!isClosed) _onPreparationFailed();
          } finally {
            ready[index].complete(message);
            if (!isClosed) preparingCount.value--;
          }
        }
      } finally {
        preparingCount.value = 0;
      }
    }

    final local = prepareLocal();
    final uploader = ChatMediaUpload(
        isClosed: () => isClosed,
        onTransfer: (message, state) => onTransfer?.call(message, state));
    await runOrderedMediaBatch<int>(
      List.generate(assets.length, (index) => index),
      prepare: (index) async {
        final message = await ready[index].future;
        if (message != null && !isClosed) await uploader.prepare(message);
      },
      send: (index) async {
        final message = messages[index];
        if (message != null) {
          await _sendMessage(message, addToUI: false, resetInput: false);
        }
      },
      onError: (index, error) {
        final message = messages[index];
        if (message != null) {
          message.status = MessageStatus.failed;
          if (onUploadFailed != null) {
            onUploadFailed!(message);
          } else {
            _onPreparationFailed();
          }
        }
      },
      isClosed: () => isClosed,
    );
    await local;
  }

  bool _pickingAttachment = false;
  Future<File> _retainAttachment(String path) async {
    final name = p.basename(path);
    final directory = Directory('${Config.cachePath}/outgoing_media');
    await directory.create(recursive: true);
    // Clock precision can repeat across fast selections. Reserve a unique
    // directory so a later attachment cannot overwrite an active upload.
    final attachmentDirectory = await directory.createTemp('attachment-');
    return File(path).copy(p.join(attachmentDirectory.path, name));
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
      if (asset != null && !isClosed) {
        closeToolbox();
        await _sendSelectedAssets([asset]);
      }
    } catch (_) {
      if (!isClosed) _onPreparationFailed();
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

  Future<Message?> _prepareAsset(AssetEntity asset,
      {ChatVideoQuality quality = ChatVideoQuality.original}) async {
    Logger.print(
        '--------assets type-----${asset.type} create time: ${asset.createDateTime}');
    final originalFile = await asset.file;
    if (isClosed) return null;
    if (originalFile == null) {
      throw StateError('Selected asset file is unavailable');
    }
    final path = originalFile.path;
    Logger.print('--------assets path-----$path');
    switch (asset.type) {
      case AssetType.image:
        return _preparePicture(path);
      case AssetType.video:
        final prepared = await prepareChatVideo(originalFile, quality);
        if (isClosed) return null;
        final saved = await _retainAttachment(prepared.path);
        if (isClosed) return null;
        final thumbnail =
            await asset.thumbnailDataWithSize(const ThumbnailSize(640, 640));
        if (isClosed) return null;
        if (thumbnail == null) {
          throw StateError('Video thumbnail unavailable');
        }
        final snapshot = File('${saved.path}.jpg');
        await snapshot.writeAsBytes(thumbnail);
        final mimeType = prepared.path != path
            ? 'video/mp4'
            : await asset.mimeTypeAsync ?? 'video/mp4';
        if (isClosed) return null;
        final message = await OpenIM.iMManager.messageManager
            .createVideoMessageFromFullPath(
                videoPath: saved.path,
                videoType: mimeType,
                duration: asset.videoDuration.inSeconds < 1
                    ? 1
                    : asset.videoDuration.inSeconds,
                snapshotPath: snapshot.path);
        if (isClosed) return null;
        return message;
      default:
        throw StateError('Unsupported asset type');
    }
  }
}
