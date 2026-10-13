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
import 'upload/chat_media_outbox.dart';
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
    this.acceptSendTask,
    this.onUploadFailed,
    Future<List<AssetEntity>?> Function()? pickAssets,
    Future<AssetEntity?> Function()? pickCamera,
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
        _pickCamera = pickCamera,
        _compressImage = compressImage ?? IMUtils.compressImageAndGetFile,
        _onPreparationFailed =
            onPreparationFailed ?? (() => IMViews.showToast(StrRes.sendFailed));

  final MediaSendTask Function()? acceptSendTask;
  final String Function() _conversationID;
  final bool Function() _isClosed, _sendingMuted, _isInvalidGroup, _voiceBusy;
  final MediaMessageSender _sendMessage;
  final void Function(Message) _stageMessage;
  final Future<void> Function(File, int) _previewAndSendVoice;
  final void Function() closeToolbox;
  final void Function(Message, ChatTransferStatus)? onTransfer;
  final void Function(Message)? onUploadFailed;
  final Future<List<AssetEntity>?> Function()? _pickAssets;
  final Future<AssetEntity?> Function()? _pickCamera;
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
    final conversation = _conversationID();
    final account = OpenIM.iMManager.userID;
    final messages = <String, Message>{};
    for (var page = 1; !isClosed; page++) {
      final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
          conversationID: conversation,
          messageTypeList: [MessageType.picture, MessageType.video],
          pageIndex: page,
          count: 200);
      if (isClosed ||
          _conversationID() != conversation ||
          OpenIM.iMManager.userID != account) {
        return [];
      }
      final batch = [
        for (final item in result.searchResultItems ?? <SearchResultItems>[])
          ...?item.messageList,
      ];
      var added = 0;
      for (final message in batch) {
        final id = message.clientMsgID;
        if (id != null && id.isNotEmpty && !messages.containsKey(id)) {
          messages[id] = message;
          added++;
        }
      }
      if (batch.length < 200 || added == 0) break;
    }
    return messages.values.toList()
      ..sort((a, b) => (a.sendTime ?? 0).compareTo(b.sendTime ?? 0));
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

  Future<Message?> _preparePicture(String path,
      {bool Function()? cancelled}) async {
    final stopped = cancelled ?? () => isClosed;
    if (stopped()) return null;
    // Keep the source and compression target unique while earlier photos upload.
    final original = await _retainAttachment(path);
    if (stopped()) return null;
    if (await original.length() == 0) {
      throw StateError('Image file is empty');
    }
    var file = original;
    try {
      final compressed = await _compressImage(original);
      if (stopped()) return null;
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
    if (stopped()) return null;
    final message =
        await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
      imagePath: file.path,
    );
    if (stopped()) return null;
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
      IMViews.showErrorToast(error);
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
    final releaseSelection = _lockAttachmentSelection();
    try {
      final assets = await (_pickAssets?.call() ?? _selectAlbumAssets());
      if (assets != null && assets.isNotEmpty && !isClosed) {
        closeToolbox();
        await _sendSelectedAssets(assets, onPrepared: releaseSelection);
      }
    } catch (_) {
      if (!isClosed) _onPreparationFailed();
    } finally {
      releaseSelection();
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

  Future<void> _sendSelectedAssets(List<AssetEntity> assets,
      {required void Function() onPrepared}) async {
    final quality = assets.any((asset) => asset.type == AssetType.video)
        ? await chooseChatVideoQuality()
        : ChatVideoQuality.original;
    if (quality == null || isClosed) return;
    // Only picker/quality dialogs are exclusive. Local preparation and upload
    // must not prevent opening the next attachment picker.
    final task = acceptSendTask?.call();
    bool stopped() => task != null ? !task.current : isClosed;
    onPrepared();
    final ready = List.generate(assets.length, (_) => Completer<Message?>());
    final messages = <int, Message>{};
    preparingCount.value += assets.length;
    Future<void> prepareLocal() async {
      try {
        for (var index = 0; index < assets.length; index++) {
          Message? message;
          try {
            if (!stopped()) {
              message = await _prepareAsset(assets[index],
                  quality: quality, cancelled: stopped);
              if (message != null && !stopped()) {
                messages[index] = message;
                if (task != null) {
                  task.stage(message);
                } else if (!isClosed) {
                  _stageMessage(message);
                }
                if (!isClosed) {
                  onTransfer?.call(message,
                      const ChatTransferStatus(ChatTransferStage.queued));
                }
              }
            }
          } catch (_) {
            // Accepted work may fail before the SDK can create a message.
            // Report that failure even if its original route has gone away.
            if (task?.current == true || !isClosed) _onPreparationFailed();
          } finally {
            ready[index].complete(message);
            if (!_closed) preparingCount.value--;
          }
        }
      } finally {
        onPrepared();
      }
    }

    final local = prepareLocal();
    final uploader = ChatMediaUpload(
        isClosed: stopped,
        onTransfer: (message, state) {
          task?.transfer(message, state);
          if (!isClosed) onTransfer?.call(message, state);
        });
    await runOrderedMediaBatch<int>(
      List.generate(assets.length, (index) => index),
      prepare: (index) async {
        final message = await ready[index].future;
        if (message != null && !stopped()) await uploader.prepare(message);
      },
      send: (index) async {
        final message = messages[index];
        if (message != null) {
          if (task != null) {
            await task.send(message);
          } else {
            await _sendMessage(message, addToUI: false, resetInput: false);
          }
        }
      },
      onError: (index, error) {
        final message = messages[index];
        if (message != null) {
          task?.failed(message);
          message.status = MessageStatus.failed;
          if (isClosed) return;
          if (onUploadFailed != null) {
            onUploadFailed!(message);
          } else {
            _onPreparationFailed();
          }
        }
      },
      isClosed: stopped,
    );
    await local;
  }

  bool _pickingAttachment = false;
  void Function() _lockAttachmentSelection() {
    _pickingAttachment = true;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _pickingAttachment = false;
    };
  }

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
    if (_pickingAttachment ||
        _voiceBusy() ||
        isClosed ||
        sendingMuted ||
        isInvalidGroup) return;
    final releaseSelection = _lockAttachmentSelection();
    try {
      final asset = await (_pickCamera?.call() ??
          CameraPicker.pickFromCamera(Get.context!,
              pickerConfig: const CameraPickerConfig(
                  enableRecording: true,
                  enableAudio: true,
                  maximumRecordingDuration: Duration(seconds: 60))));
      if (asset != null && !isClosed) {
        closeToolbox();
        await _sendSelectedAssets([asset], onPrepared: releaseSelection);
      }
    } catch (_) {
      if (!isClosed) _onPreparationFailed();
    } finally {
      releaseSelection();
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
    final releaseSelection = _lockAttachmentSelection();
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
      releaseSelection();
      if (!isClosed) await _sendMessage(message);
    } catch (_) {
      IMViews.showToast(StrRes.sendFailed);
    } finally {
      if (unclaimedAudio != null) {
        try {
          if (await unclaimedAudio.exists()) await unclaimedAudio.delete();
        } catch (_) {}
      }
      releaseSelection();
    }
  }

  Future<bool> allowSendImageType(AssetEntity entity) async {
    final mimeType = await entity.mimeTypeAsync;

    return IMUtils.allowImageType(mimeType);
  }

  Future<Message?> _prepareAsset(AssetEntity asset,
      {ChatVideoQuality quality = ChatVideoQuality.original,
      bool Function()? cancelled}) async {
    final stopped = cancelled ?? () => isClosed;
    Logger.print(
        '--------assets type-----${asset.type} create time: ${asset.createDateTime}');
    final originalFile = await asset.file;
    if (stopped()) return null;
    if (originalFile == null) {
      throw StateError('Selected asset file is unavailable');
    }
    final path = originalFile.path;
    Logger.print('--------assets path-----$path');
    switch (asset.type) {
      case AssetType.image:
        return _preparePicture(path, cancelled: stopped);
      case AssetType.video:
        final prepared = await prepareChatVideo(originalFile, quality);
        if (stopped()) return null;
        final saved = await _retainAttachment(prepared.path);
        if (stopped()) return null;
        final thumbnail =
            await asset.thumbnailDataWithSize(const ThumbnailSize(640, 640));
        if (stopped()) return null;
        if (thumbnail == null) {
          throw StateError('Video thumbnail unavailable');
        }
        final snapshot = File('${saved.path}.jpg');
        await snapshot.writeAsBytes(thumbnail);
        final mimeType = prepared.path != path
            ? 'video/mp4'
            : await asset.mimeTypeAsync ?? 'video/mp4';
        if (stopped()) return null;
        final message = await OpenIM.iMManager.messageManager
            .createVideoMessageFromFullPath(
                videoPath: saved.path,
                videoType: mimeType,
                duration: asset.videoDuration.inSeconds < 1
                    ? 1
                    : asset.videoDuration.inSeconds,
                snapshotPath: snapshot.path);
        if (stopped()) return null;
        return message;
      default:
        throw StateError('Unsupported asset type');
    }
  }
}
