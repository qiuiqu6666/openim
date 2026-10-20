import 'package:openim_common/media_localization.dart';
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

import 'upload/ready_media_batch.dart';
import 'upload/chat_media_outbox.dart';
import 'upload/chat_media_upload.dart';
import 'video/chat_video_preparation.dart';
import 'preparation/chat_media_asset_loader.dart';
import 'diagnostics/chat_media_diagnostics.dart';

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
    Future<bool?> Function()? chooseOriginal,
    this.assetReadTimeout = const Duration(seconds: 30),
    this.imageCompressionTimeout = const Duration(seconds: 10),
    this.messageCreationTimeout = const Duration(seconds: 15),
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
        _compressImage = compressImage ?? _compressChatImage,
        _chooseOriginal = chooseOriginal ?? (() async => false),
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
  final Future<bool?> Function() _chooseOriginal;
  final void Function() _onPreparationFailed;
  final Duration assetReadTimeout,
      imageCompressionTimeout,
      messageCreationTimeout;
  final tempMessages = <Message>[];
  final preparingCount = 0.obs;
  final failedPreparationCount = 0.obs;
  final _preparationRetries = <void Function()>[];

  void retryPreparation() {
    if (isClosed || sendingMuted || isInvalidGroup) return;
    final retries = List.of(_preparationRetries);
    _preparationRetries.clear();
    failedPreparationCount.value = 0;
    for (final retry in retries) {
      retry();
    }
  }

  bool _closed = false;
  bool get isClosed => _closed || _isClosed();
  bool get sendingMuted => _sendingMuted();
  bool get isInvalidGroup => _isInvalidGroup();
  bool get pickingAttachment => _pickingAttachment;

  void close() {
    _closed = true;
    tempMessages.clear();
    preparingCount.value = 0;
    _preparationRetries.clear();
    failedPreparationCount.value = 0;
  }

  Future<List<Message>> searchMediaMessage(
      {bool Function()? continueLoading}) async {
    final conversation = _conversationID();
    final account = OpenIM.iMManager.userID;
    final messages = <String, Message>{};
    for (var page = 1; !isClosed && (continueLoading?.call() ?? true); page++) {
      final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
          conversationID: conversation,
          messageTypeList: [MessageType.picture, MessageType.video],
          pageIndex: page,
          count: 200);
      if (isClosed ||
          !(continueLoading?.call() ?? true) ||
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

  Future sendPicture(
      {required String path,
      bool sendNow = true,
      bool original = false}) async {
    try {
      final message = await _preparePicture(path, originalQuality: original);
      if (message == null || isClosed) return;
      if (sendNow) {
        return await _sendMessage(message);
      } else {
        _stageMessage(message);
        tempMessages.add(message);
      }
    } catch (error) {
      ChatMediaDiagnostics.record('send_picture',
          outcome: 'failed', error: error);
      if (!isClosed) _onPreparationFailed();
    }
  }

  /// Prepare an image without posting it; composite messages upload all parts
  /// before submitting their single SDK envelope.
  Future<Message?> preparePicture(String path) => _preparePicture(path);

  Future<Message?> _preparePicture(String path,
      {bool Function()? cancelled,
      ChatMediaTrace? trace,
      bool originalQuality = false}) async {
    trace ??= ChatMediaTrace();
    final stopped = cancelled ?? () => isClosed;
    if (stopped()) return null;
    // Keep the source and compression target unique while earlier photos upload.
    final original = await trace.run('retain_image',
        () => _retainAttachment(path).timeout(assetReadTimeout));
    if (stopped()) return null;
    if (await original.length() == 0) {
      throw StateError('Image file is empty');
    }
    var file = original;
    final conversionRequired =
        {'.heic', '.heif'}.contains(p.extension(path).toLowerCase());
    try {
      final compressed = originalQuality && !conversionRequired
          ? original
          : await trace.run(
              'compress_image',
              () => (originalQuality
                      ? IMUtils.compressImageAndGetFile(original,
                          quality: 100, convertToJpeg: true)
                      : _compressImage(original))
                  .timeout(imageCompressionTimeout));
      if (stopped()) return null;
      if (compressed != null &&
          await compressed.exists() &&
          await compressed.length() > 0 &&
          (conversionRequired ||
              await compressed.length() <= await original.length())) {
        file = compressed;
      }
    } catch (error) {
      if (conversionRequired) rethrow;
      // Compression is optional. A readable local source can still be sent.
      trace.record('compress_image', outcome: 'source_fallback', error: error);
    }
    if (stopped()) return null;
    if (conversionRequired &&
        !{'.jpg', '.jpeg'}.contains(p.extension(file.path).toLowerCase())) {
      trace.record('convert_heif', outcome: 'no_jpeg_output');
      throw StateError('HEIF conversion did not produce JPEG');
    }
    final message = await trace.run(
        'create_message',
        () => OpenIM.iMManager.messageManager
            .createImageMessageFromFullPath(
              imagePath: file.path,
              operationID: trace!.id,
            )
            .timeout(messageCreationTimeout));
    trace.messageID = message.clientMsgID;
    trace.record('image_ready');
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
    if (_pickerBlocked('album_picker')) return;
    final releaseSelection = _lockAttachmentSelection();
    final trace = ChatMediaTrace();
    try {
      final assets = await trace.run(
          'album_picker', () => _pickAssets?.call() ?? _selectAlbumAssets());
      trace.record('album_selection', count: assets?.length ?? 0);
      if (assets != null && assets.isNotEmpty && !isClosed) {
        closeToolbox();
        await _sendSelectedAssets(assets, onPrepared: releaseSelection);
      }
    } catch (error) {
      trace.record('album', outcome: 'failed', error: error);
      if (!isClosed) _onPreparationFailed();
    } finally {
      releaseSelection();
    }
  }

  Future<List<AssetEntity>?> _selectAlbumAssets() =>
      AssetPicker.pickAssets(Get.context!,
          pickerConfig: AssetPickerConfig(
              textDelegate: AppMediaCopy.assets,
              requestType: RequestType.common,
              sortPathsByModifiedDate: true,
              filterOptions: PMFilter.defaultValue(containsPathModified: true),
              selectPredicate: (_, entity, isSelected) async {
                if (isSelected) return true;
                if (entity.type == AssetType.image) {
                  if (await allowSendImageType(entity)) {
                    return true;
                  }

                  IMViews.showToast(StrRes.supportsTypeHint);

                  return false;
                }

                if (entity.videoDuration > const Duration(hours: 1)) {
                  IMViews.showToast(
                      sprintf(StrRes.selectVideoLimit, [60]) + StrRes.minute);
                  return false;
                }
                return true;
              }));

  Future<void> _sendSelectedAssets(List<AssetEntity> assets,
      {required void Function() onPrepared,
      bool? originalChoice,
      MediaSendTask? acceptedTask}) async {
    final original = originalChoice ?? await _chooseOriginal();
    if (original == null || isClosed) return;
    final quality =
        original ? ChatVideoQuality.original : ChatVideoQuality.standard;
    // Only picker/quality dialogs are exclusive. Local preparation and upload
    // must not prevent opening the next attachment picker.
    final task = acceptedTask ?? acceptSendTask?.call();
    var reportedCancellation = false;
    bool stopped() {
      final cancelled = task != null ? !task.current : isClosed;
      if (cancelled && !reportedCancellation) {
        reportedCancellation = true;
        ChatMediaDiagnostics.record('media_batch', outcome: 'session_changed');
        if (task?.visible == true && !isClosed) _onPreparationFailed();
      }
      return cancelled;
    }

    onPrepared();
    final ready = List.generate(assets.length, (_) => Completer<Message?>());
    final messages = <int, Message>{};
    preparingCount.value += assets.length;
    Future<void> prepareItem(int index) async {
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
              onTransfer?.call(
                  message, const ChatTransferStatus(ChatTransferStage.queued));
            }
          }
        }
      } catch (error) {
        ChatMediaDiagnostics.record('prepare_asset',
            outcome: 'failed', error: error);
        // Accepted work may fail before the SDK can create a message.
        // Report that failure even if its original route has gone away.
        if (task?.current == true || !isClosed) _onPreparationFailed();
        if (!isClosed && !stopped()) {
          _preparationRetries.add(() {
            if (stopped()) return;
            unawaited(_sendSelectedAssets([assets[index]],
                onPrepared: () {},
                originalChoice: original,
                acceptedTask: task));
          });
          failedPreparationCount.value = _preparationRetries.length;
        }
      } finally {
        ready[index].complete(message);
        if (!_closed) preparingCount.value--;
      }
    }

    // Keep video encoding waits out of the image lane. Each lane is bounded,
    // so a slow item cannot hold every later attachment or flood native IO.
    Future<void> lane(bool videos) async {
      final indices = [
        for (var i = 0; i < assets.length; i++)
          if ((assets[i].type == AssetType.video) == videos) i
      ];
      var cursor = 0;
      Future<void> worker() async {
        while (cursor < indices.length) {
          await prepareItem(indices[cursor++]);
        }
      }

      await Future.wait([worker(), worker()]);
    }

    final local = Future.wait([lane(false), lane(true)]);
    final uploader = ChatMediaUpload(
        isClosed: stopped,
        onTransfer: (message, state) {
          task?.transfer(message, state);
          if (!isClosed) onTransfer?.call(message, state);
        });
    await runReadyMediaBatch<int>(
      List.generate(assets.length, (index) => index),
      isVideo: (index) => assets[index].type == AssetType.video,
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
        ChatMediaDiagnostics.record('upload_or_send',
            messageID: message?.clientMsgID, outcome: 'failed', error: error);
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
  bool _pickerBlocked(String stage) {
    final reason = isClosed
        ? 'session_closed'
        : sendingMuted
            ? 'muted'
            : isInvalidGroup
                ? 'invalid_group'
                : _pickingAttachment
                    ? 'picker_busy'
                    : _voiceBusy()
                        ? 'voice_busy'
                        : null;
    if (reason == null) return false;
    ChatMediaDiagnostics.record(stage, outcome: reason);
    return true;
  }

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
    if (_pickerBlocked('camera_picker')) return;
    final releaseSelection = _lockAttachmentSelection();
    final trace = ChatMediaTrace();
    try {
      final asset = await trace.run(
          'camera_picker',
          () =>
              _pickCamera?.call() ??
              CameraPicker.pickFromCamera(Get.context!,
                  pickerConfig: CameraPickerConfig(
                      textDelegate: AppMediaCopy.camera,
                      enableRecording: true,
                      enableAudio: true,
                      maximumRecordingDuration: Duration(seconds: 60))));
      if (asset != null && !isClosed) {
        closeToolbox();
        await _sendSelectedAssets([asset], onPrepared: releaseSelection);
      }
    } catch (error) {
      trace.record('camera', outcome: 'failed', error: error);
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
    if (entity.type != AssetType.image) return false;
    String? mimeType;
    try {
      mimeType =
          (await entity.mimeTypeAsync.timeout(const Duration(seconds: 2)))
              ?.trim()
              .toLowerCase();
    } catch (error) {
      ChatMediaDiagnostics.record('image_metadata',
          outcome: 'deferred', error: error);
    }
    // Metadata may be absent for cloud/limited-library assets. The actual file
    // still has to pass compression and SDK decoding before it can be sent.
    final allowed = mimeType == null ||
        mimeType.isEmpty ||
        mimeType == 'application/octet-stream' ||
        mimeType.startsWith('image/heif') ||
        IMUtils.allowImageType(mimeType);
    if (!allowed) {
      ChatMediaDiagnostics.record('image_metadata',
          outcome: 'unsupported_type');
    }
    return allowed;
  }

  Future<Message?> _prepareAsset(AssetEntity asset,
      {ChatVideoQuality quality = ChatVideoQuality.standard,
      bool Function()? cancelled}) async {
    final stopped = cancelled ?? () => isClosed;
    final trace = ChatMediaTrace();
    final originalFile = await trace.run(
        'load_asset',
        () => loadChatMediaAsset(asset,
            timeout: assetReadTimeout,
            isCancelled: stopped,
            onReadFailure: (stage, error) =>
                trace.record(stage, outcome: 'failed', error: error)));
    if (stopped()) return null;
    if (originalFile == null) {
      throw StateError('Selected asset file is unavailable');
    }
    final path = originalFile.path;
    switch (asset.type) {
      case AssetType.image:
        return _preparePicture(path,
            cancelled: stopped,
            trace: trace,
            originalQuality: quality == ChatVideoQuality.original);
      case AssetType.video:
        final prepared = await trace.run(
            'compress_video', () => prepareChatVideo(originalFile, quality));
        if (stopped()) return null;
        final saved = await trace.run('retain_video',
            () => _retainAttachment(prepared.path).timeout(assetReadTimeout));
        if (stopped()) return null;
        final thumbnail = await trace.run(
            'video_thumbnail',
            () => asset
                .thumbnailDataWithSize(const ThumbnailSize(640, 640))
                .timeout(assetReadTimeout));
        if (stopped()) return null;
        if (thumbnail == null) {
          throw StateError('Video thumbnail unavailable');
        }
        final snapshot = File('${saved.path}.jpg');
        await snapshot.writeAsBytes(thumbnail).timeout(assetReadTimeout);
        final mimeType = prepared.path != path
            ? 'video/mp4'
            : await asset.mimeTypeAsync.timeout(assetReadTimeout) ??
                'video/mp4';
        if (stopped()) return null;
        final message = await trace.run(
            'create_video_message',
            () => OpenIM.iMManager.messageManager
                .createVideoMessageFromFullPath(
                    videoPath: saved.path,
                    videoType: mimeType,
                    duration: asset.videoDuration.inSeconds < 1
                        ? 1
                        : asset.videoDuration.inSeconds,
                    snapshotPath: snapshot.path)
                .timeout(messageCreationTimeout));
        if (stopped()) return null;
        return message;
      default:
        throw StateError('Unsupported asset type');
    }
  }
}

Future<File?> _compressChatImage(File file) => IMUtils.compressImageAndGetFile(
    file,
    // The OpenIM core has no HEIF decoder. Export a real JPEG, with a matching
    // suffix, before asking the SDK to create the image message.
    convertToJpeg:
        {'.heic', '.heif'}.contains(p.extension(file.path).toLowerCase()));
