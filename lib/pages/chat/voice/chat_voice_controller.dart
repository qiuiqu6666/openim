import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'voice_to_text_service.dart';
import 'voice_transcription_controller.dart';
import 'widgets/voice_text_preview_dialog.dart';

typedef ChatVoiceSender = Future<void> Function(Message message,
    {bool resetInput});
typedef ChatVoiceLocalWriter = Future<void> Function(
    {required String conversationID,
    required String clientMsgID,
    required String localEx});
typedef ChatVoiceFileTranscriber = Future<String> Function(CancelToken token);
typedef ChatVoicePreview = Future<VoiceTextChoice?> Function(
    ChatVoiceFileTranscriber transcribe);

/// Owns the voice jobs, playback, local writes and recording/preview lifecycle
/// for one chat route. The route supplies only the capabilities voice needs.
class ChatVoiceController {
  ChatVoiceController({
    required this.conversationID,
    required List<Message> Function() messages,
    required Iterable<Message> Function() bufferedMessages,
    required bool Function(String? id) isMessageRemoved,
    required Future<void> Function(Message message) markMessageRead,
    required ChatVoiceSender sendMessage,
    required bool Function() canSend,
    bool Function()? attachmentBusy,
    VoiceToTextService? service,
    String Function()? accountProvider,
    String? Function()? tokenProvider,
    ChatVoiceLocalWriter? writeLocalEx,
    Future<Message> Function(String path, int seconds)? createSoundMessage,
    Future<Message> Function(String text)? createTextMessage,
    ChatVoicePreview? preview,
    Future<Map<String, dynamic>?> Function()? captureRecording,
    void Function()? showSendFailure,
  })  : service = service ?? VoiceToTextService(),
        _messages = messages,
        _bufferedMessages = bufferedMessages,
        _isMessageRemoved = isMessageRemoved,
        _markMessageRead = markMessageRead,
        _sendMessage = sendMessage,
        _canSend = canSend,
        _attachmentBusy = attachmentBusy ?? (() => false),
        _accountProvider = accountProvider ?? (() => OpenIM.iMManager.userID),
        _tokenProvider = tokenProvider ?? (() => DataSp.chatToken),
        _writeLocalEx = writeLocalEx ??
            ((
                    {required conversationID,
                    required clientMsgID,
                    required localEx}) =>
                OpenIM.iMManager.messageManager.setMessageLocalEx(
                    conversationID: conversationID,
                    clientMsgID: clientMsgID,
                    localEx: localEx)),
        _createSoundMessage = createSoundMessage ??
            ((path, seconds) => OpenIM.iMManager.messageManager
                .createSoundMessageFromFullPath(
                    soundPath: path, duration: seconds)),
        _createTextMessage = createTextMessage ??
            ((text) =>
                OpenIM.iMManager.messageManager.createTextMessage(text: text)),
        _preview = preview ??
            ((transcribe) => VoiceTextPreviewDialog.show(Get.context!,
                transcribe: transcribe)),
        _captureRecording = captureRecording ??
            (() => Get.dialog<Map<String, dynamic>>(const VoiceCaptureDialog(),
                barrierDismissible: false)),
        _showSendFailure =
            showSendFailure ?? (() => IMViews.showToast(StrRes.sendFailed)) {
    transcriptions = VoiceTranscriptionController(
        service: this.service, persist: _writeVoiceLocalEx);
    playback =
        VoicePlaybackController(messages: _messages, onPlayed: markVoicePlayed);
  }

  final String conversationID;
  final VoiceToTextService service;
  late final VoiceTranscriptionController transcriptions;
  late final VoicePlaybackController playback;
  final List<Message> Function() _messages;
  final Iterable<Message> Function() _bufferedMessages;
  final bool Function(String?) _isMessageRemoved;
  final Future<void> Function(Message) _markMessageRead;
  final ChatVoiceSender _sendMessage;
  final bool Function() _canSend;
  final bool Function() _attachmentBusy;
  final String Function() _accountProvider;
  final String? Function() _tokenProvider;
  final ChatVoiceLocalWriter _writeLocalEx;
  final Future<Message> Function(String, int) _createSoundMessage;
  final Future<Message> Function(String) _createTextMessage;
  final ChatVoicePreview _preview;
  final Future<Map<String, dynamic>?> Function() _captureRecording;
  final void Function() _showSendFailure;
  final _localWrites = <String, Future<void>>{};
  final _removedIDs = <String>{};
  bool _closed = false;
  bool _previewOpen = false;
  bool _recordingOpen = false;

  bool get isClosed => _closed;
  bool get previewOpen => _previewOpen;
  bool get recordingOpen => _recordingOpen;
  bool get busy => _previewOpen || _recordingOpen;

  bool _removed(String? id) =>
      _removedIDs.contains(id) || _isMessageRemoved(id);

  bool _active(String accountID, String? token) =>
      !_closed && accountID == _accountProvider() && token == _tokenProvider();

  Future<void> markVoicePlayed(Message message) async {
    final accountID = _accountProvider();
    final token = _tokenProvider();
    await _writeVoiceLocalEx(message, {'voiceHeard': true});
    if (_active(accountID, token) && !_removed(message.clientMsgID)) {
      await _markMessageRead(message);
    }
  }

  /// Recognition and playback share one per-ID queue and merge the latest
  /// message localEx after earlier writes finish, rather than a stale snapshot.
  Future<void> _writeVoiceLocalEx(
      Message message, Map<String, dynamic> patch) async {
    final id = message.clientMsgID;
    if (_closed || id == null || id.isEmpty || _removed(id)) return;
    final accountID = _accountProvider();
    final token = _tokenProvider();
    final previous = _localWrites[id] ?? Future<void>.value();
    final write = previous.catchError((Object _) {}).then((_) async {
      if (!_active(accountID, token) || _removed(id)) return;
      final latest = _messages()
              .where((m) => m.clientMsgID == id)
              .firstOrNull ??
          _bufferedMessages().where((m) => m.clientMsgID == id).firstOrNull ??
          message;
      Map<String, dynamic> extra = {};
      try {
        extra = Map<String, dynamic>.from(jsonDecode(latest.localEx ?? '{}'));
      } catch (_) {}
      final encoded = jsonEncode({...extra, ...patch});
      if (encoded == latest.localEx) return;
      await _writeLocalEx(
          conversationID: conversationID, clientMsgID: id, localEx: encoded);
      if (!_active(accountID, token) || _removed(id)) return;
      message.localEx = encoded;
      for (final item in [..._messages(), ..._bufferedMessages()]) {
        if (item.clientMsgID == id) item.localEx = encoded;
      }
    });
    _localWrites[id] = write;
    try {
      await write;
    } finally {
      if (identical(_localWrites[id], write)) _localWrites.remove(id);
    }
  }

  bool canTranscribeVoice(Message message) =>
      !_closed &&
      !_removed(message.clientMsgID) &&
      transcriptions.canTranscribe(message);

  Future<void> transcribeVoice(Message message) async {
    if (!canTranscribeVoice(message)) return;
    final accountID = _accountProvider();
    final token = _tokenProvider();
    if (message.attachedInfoElem?.isPrivateChat == true) {
      await _markMessageRead(message);
      if (!_active(accountID, token) || !canTranscribeVoice(message)) return;
    }
    await transcriptions.transcribe(message);
  }

  VoiceTranscriptionState? displayedVoiceTranscription(Message message) {
    if (!canTranscribeVoice(message)) return null;
    final state = transcriptions.stateFor(message);
    return state.loading || state.hasText || state.error != null ? state : null;
  }

  void removeMessage(String id) {
    _removedIDs.add(id);
    transcriptions.remove(id);
  }

  Future<void> onTapRecord() async {
    if (_closed || busy || _attachmentBusy() || !_canSend()) return;
    _recordingOpen = true;
    final accountID = _accountProvider();
    final token = _tokenProvider();
    try {
      final result = await _captureRecording();
      if (result == null) return;
      final path = result['path'] as String;
      if (!_active(accountID, token) || !_canSend()) {
        await _deleteFile(File(path));
        return;
      }
      final seconds = result['duration'] as int;
      if (result['convertToText'] == true) {
        await convertRecordedVoice(path, seconds);
      } else {
        await sendRecordedVoice(path, seconds);
      }
    } finally {
      _recordingOpen = false;
    }
  }

  Future<void> convertRecordedVoice(String path, int seconds) =>
      previewAndSendVoice(File(path), seconds);

  Future<void> previewAndSendVoice(File file, int seconds) async {
    bool keepForMessage = false;
    bool ownsPreview = false;
    final accountID = _accountProvider();
    final token = _tokenProvider();
    try {
      if (!_active(accountID, token) || _previewOpen || !_canSend()) return;
      _previewOpen = ownsPreview = true;
      final choice = await _preview((cancelToken) => service
          .transcribeFile(file, duration: seconds, cancelToken: cancelToken));
      if (choice == null || !_active(accountID, token) || !_canSend()) return;
      if (choice.sendOriginal) {
        final message = await _createSoundMessage(file.path, seconds);
        if (!_active(accountID, token) || !_canSend()) return;
        keepForMessage = true;
        await _sendMessage(message, resetInput: true);
      } else {
        final text = choice.text?.trim() ?? '';
        if (text.isEmpty) return;
        final message = await _createTextMessage(text);
        if (_active(accountID, token) && _canSend()) {
          await _sendMessage(message, resetInput: false);
        }
      }
    } catch (_) {
      if (_active(accountID, token)) _showSendFailure();
    } finally {
      if (ownsPreview) _previewOpen = false;
      if (!keepForMessage) await _deleteFile(file);
    }
  }

  Future<void> sendRecordedVoice(String path, int seconds) async {
    if (_closed || !_canSend()) return;
    final accountID = _accountProvider();
    final token = _tokenProvider();
    try {
      final message = await _createSoundMessage(path, seconds);
      if (_active(accountID, token) && _canSend()) {
        await _sendMessage(message, resetInput: true);
      }
    } catch (_) {
      if (_active(accountID, token)) _showSendFailure();
    }
  }

  static Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    transcriptions.dispose();
    service.dispose();
    playback.dispose();
    _localWrites.clear();
    _removedIDs.clear();
  }
}
