import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/voice/chat_voice_controller.dart';
import 'package:openim/pages/chat/voice/voice_to_text_service.dart';
import 'package:openim/pages/chat/voice/widgets/voice_text_preview_dialog.dart';

class _VoiceService extends VoiceToTextService {
  final answer = Completer<String>();
  final tokens = <CancelToken?>[];
  int disposals = 0;

  @override
  Future<String> transcribeMessage(Message message,
      {CancelToken? cancelToken}) {
    tokens.add(cancelToken);
    return answer.future;
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _VoiceFixture {
  final service = _VoiceService();
  final messages = <Message>[];
  final buffer = <Message>[];
  final removed = <String>{};
  final writes = <Map<String, dynamic>>[];
  final reads = <Message>[];
  final sent = <({Message message, bool resetInput})>[];
  final writerGate = Completer<void>();
  final previewGate = Completer<VoiceTextChoice?>();
  final captureGate = Completer<Map<String, dynamic>?>();
  String account = 'self';
  String token = 'token';
  bool allowSend = true;
  bool attachmentBusy = false;
  bool holdWrites = false;
  int previews = 0;
  int captures = 0;
  int created = 0;
  Completer<void>? messageCreationGate;
  Future<void> Function(Message)? onRead;

  late final voice = ChatVoiceController(
    conversationID: 'conversation',
    messages: () => messages,
    bufferedMessages: () => buffer,
    isMessageRemoved: removed.contains,
    accountProvider: () => account,
    tokenProvider: () => token,
    service: service,
    canSend: () => allowSend,
    attachmentBusy: () => attachmentBusy,
    markMessageRead: (message) async {
      reads.add(message);
      await onRead?.call(message);
    },
    sendMessage: (message, {resetInput = true}) async {
      sent.add((message: message, resetInput: resetInput));
    },
    writeLocalEx: (
        {required conversationID,
        required clientMsgID,
        required localEx}) async {
      expect(conversationID, 'conversation');
      writes.add({'id': clientMsgID, ...jsonDecode(localEx) as Map});
      if (holdWrites) await writerGate.future;
    },
    createTextMessage: (text) async {
      created++;
      await messageCreationGate?.future;
      return Message(clientMsgID: 'text', textElem: TextElem(content: text));
    },
    createSoundMessage: (path, seconds) async {
      created++;
      await messageCreationGate?.future;
      return Message(
          clientMsgID: 'sound',
          soundElem: SoundElem(soundPath: path, duration: seconds));
    },
    preview: (_) {
      previews++;
      return previewGate.future;
    },
    captureRecording: () {
      captures++;
      return captureGate.future;
    },
    showSendFailure: () {},
  );
}

Message _voiceMessage([String id = 'voice']) => Message(
    clientMsgID: id,
    contentType: MessageType.voice,
    localEx: '{"unrelated":42}',
    soundElem: SoundElem(duration: 4));

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _VoiceFixture fixture;

  setUp(() => fixture = _VoiceFixture());
  tearDown(() => fixture.voice.dispose());

  test('playback and recognition serialize local writes and merge both patches',
      () async {
    final message = _voiceMessage();
    fixture.messages.add(message);
    fixture.holdWrites = true;
    final played = fixture.voice.markVoicePlayed(message);
    await _flush();
    final recognized = fixture.voice.transcribeVoice(message);
    await _flush();
    fixture.service.answer.complete('recognized words');
    await _flush();
    expect(fixture.writes, hasLength(1));
    fixture.writerGate.complete();
    await Future.wait([played, recognized]);
    expect(fixture.writes, [
      {'id': 'voice', 'unrelated': 42, 'voiceHeard': true},
      {
        'id': 'voice',
        'unrelated': 42,
        'voiceHeard': true,
        'voiceToText': 'recognized words',
        'voiceToTextDisplayState': 'expanded',
      },
    ]);
    expect(jsonDecode(message.localEx!)['voiceToText'], 'recognized words');
    expect(fixture.reads, [message]);
  });

  test('local write reads the current SDK object and updates buffered copies',
      () async {
    final stale = _voiceMessage();
    final current = _voiceMessage()..localEx = '{"unrelated":43}';
    final buffered = _voiceMessage();
    fixture.messages.add(current);
    fixture.buffer.add(buffered);
    await fixture.voice.markVoicePlayed(stale);
    expect(jsonDecode(stale.localEx!), {'unrelated': 43, 'voiceHeard': true});
    expect(buffered.localEx, current.localEx);
    expect(fixture.writes.single['unrelated'], 43);
  });

  test('different message IDs do not block each other local writes', () async {
    fixture.holdWrites = true;
    final first = fixture.voice.markVoicePlayed(_voiceMessage('first'));
    final second = fixture.voice.markVoicePlayed(_voiceMessage('second'));
    await _flush();
    expect(fixture.writes.map((w) => w['id']), ['first', 'second']);
    fixture.writerGate.complete();
    await Future.wait([first, second]);
  });

  test('close cancels recognition and suppresses queued writes and callbacks',
      () async {
    final message = _voiceMessage();
    fixture.messages.add(message);
    fixture.holdWrites = true;
    final played = fixture.voice.markVoicePlayed(message);
    await _flush();
    final recognized = fixture.voice.transcribeVoice(message);
    await _flush();
    fixture.voice.dispose();
    fixture.voice.dispose();
    expect(fixture.service.tokens.single!.isCancelled, isTrue);
    fixture.service.answer.complete('too late');
    fixture.writerGate.complete();
    await Future.wait([played, recognized]);
    expect(fixture.writes, hasLength(1));
    expect(message.localEx, '{"unrelated":42}');
    expect(fixture.reads, isEmpty);
    expect(fixture.service.disposals, 1);
    expect(fixture.voice.displayedVoiceTranscription(message), isNull);
  });

  test('removal while writing prevents applying late metadata and read receipt',
      () async {
    final message = _voiceMessage();
    fixture.messages.add(message);
    fixture.holdWrites = true;
    final played = fixture.voice.markVoicePlayed(message);
    await _flush();
    fixture.voice.removeMessage('voice');
    fixture.writerGate.complete();
    await played;
    expect(message.localEx, '{"unrelated":42}');
    expect(fixture.reads, isEmpty);
    expect(fixture.voice.canTranscribeVoice(message), isFalse);
  });

  test('account change while writing suppresses metadata and read callback',
      () async {
    final message = _voiceMessage();
    fixture.messages.add(message);
    fixture.holdWrites = true;
    final played = fixture.voice.markVoicePlayed(message);
    await _flush();
    fixture.account = 'next-account';
    fixture.writerGate.complete();
    await played;
    expect(message.localEx, '{"unrelated":42}');
    expect(fixture.reads, isEmpty);
  });

  test('private transcription waits for read and does not persist its text',
      () async {
    final message = _voiceMessage()
      ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    final read = Completer<void>();
    fixture.onRead = (_) => read.future;
    final recognized = fixture.voice.transcribeVoice(message);
    await _flush();
    expect(fixture.service.tokens, isEmpty);
    read.complete();
    await _flush();
    fixture.service.answer.complete('private words');
    await recognized;
    expect(fixture.voice.displayedVoiceTranscription(message)!.text,
        'private words');
    expect(fixture.writes, isEmpty);
    expect(message.localEx, '{"unrelated":42}');
  });

  test('close while private read is pending never starts recognition',
      () async {
    final message = _voiceMessage()
      ..attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    final read = Completer<void>();
    fixture.onRead = (_) => read.future;
    final recognized = fixture.voice.transcribeVoice(message);
    fixture.voice.dispose();
    read.complete();
    await recognized;
    expect(fixture.service.tokens, isEmpty);
  });

  test(
      'preview sends edited text without clearing the composer and deletes file',
      () async {
    final directory = await Directory.systemTemp.createTemp('voice-module-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/recording.wav').writeAsBytes([1]);
    final pending = fixture.voice.previewAndSendVoice(file, 4);
    expect(fixture.voice.previewOpen, isTrue);
    fixture.previewGate.complete(const VoiceTextChoice.text(' edited words '));
    await pending;
    expect(fixture.sent.single.message.textElem!.content, 'edited words');
    expect(fixture.sent.single.resetInput, isFalse);
    expect(await file.exists(), isFalse);
    expect(fixture.voice.previewOpen, isFalse);
  });

  test('closing a preview ignores late choice and removes unclaimed recording',
      () async {
    final directory = await Directory.systemTemp.createTemp('voice-module-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/recording.wav').writeAsBytes([1]);
    final pending = fixture.voice.previewAndSendVoice(file, 4);
    fixture.voice.dispose();
    fixture.previewGate.complete(const VoiceTextChoice.original());
    await pending;
    expect(fixture.created, 0);
    expect(fixture.sent, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test(
      'cancelling a preview deletes the recording without changing the composer',
      () async {
    final directory = await Directory.systemTemp.createTemp('voice-module-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/recording.wav').writeAsBytes([1]);
    final pending = fixture.voice.previewAndSendVoice(file, 4);
    fixture.previewGate.complete(null);
    await pending;
    expect(fixture.created, 0);
    expect(fixture.sent, isEmpty);
    expect(await file.exists(), isFalse);
    expect(fixture.voice.previewOpen, isFalse);
    expect(fixture.voice.busy, isFalse);
  });

  test('sending the original preserves its file for the message after disposal',
      () async {
    final directory = await Directory.systemTemp.createTemp('voice-module-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/recording.wav').writeAsBytes([1]);
    final pending = fixture.voice.previewAndSendVoice(file, 4);
    fixture.previewGate.complete(const VoiceTextChoice.original());
    await pending;
    expect(fixture.created, 1);
    expect(fixture.sent, hasLength(1));
    expect(fixture.sent.single.message.soundElem!.soundPath, file.path);
    expect(fixture.sent.single.message.soundElem!.duration, 4);
    expect(await file.exists(), isTrue);
    expect(fixture.voice.previewOpen, isFalse);
    fixture.voice.dispose();
    expect(await file.exists(), isTrue);
  });

  test('a second preview cannot replace or unlock the active recording',
      () async {
    final directory = await Directory.systemTemp.createTemp('voice-module-');
    addTearDown(() => directory.delete(recursive: true));
    final first = await File('${directory.path}/first.wav').writeAsBytes([1]);
    final second = await File('${directory.path}/second.wav').writeAsBytes([2]);
    final pending = fixture.voice.previewAndSendVoice(first, 4);
    await fixture.voice.previewAndSendVoice(second, 4);
    expect(fixture.previews, 1);
    expect(fixture.voice.previewOpen, isTrue);
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isFalse);
    expect(fixture.created, 0);
    fixture.previewGate.complete(const VoiceTextChoice.original());
    await pending;
    expect(fixture.sent, hasLength(1));
    expect(fixture.sent.single.message.soundElem!.soundPath, first.path);
    expect(await first.exists(), isTrue);
    expect(fixture.voice.previewOpen, isFalse);
  });

  for (final choice in ['original', 'text']) {
    test(
        'close during $choice message creation suppresses send and deletes audio',
        () async {
      final directory = await Directory.systemTemp.createTemp('voice-module-');
      addTearDown(() => directory.delete(recursive: true));
      final file =
          await File('${directory.path}/recording.wav').writeAsBytes([1]);
      final gate = fixture.messageCreationGate = Completer<void>();
      final pending = fixture.voice.previewAndSendVoice(file, 4);
      fixture.previewGate.complete(choice == 'original'
          ? const VoiceTextChoice.original()
          : const VoiceTextChoice.text('edited words'));
      await _flush();
      expect(fixture.created, 1);
      expect(fixture.sent, isEmpty);
      fixture.voice.dispose();
      gate.complete();
      await pending;
      expect(fixture.sent, isEmpty);
      expect(await file.exists(), isFalse);
      expect(fixture.voice.previewOpen, isFalse);
    });
  }

  test('recording is blocked by attachments and owns its reentry lock',
      () async {
    fixture.attachmentBusy = true;
    await fixture.voice.onTapRecord();
    expect(fixture.captures, 0);
    fixture.attachmentBusy = false;
    final first = fixture.voice.onTapRecord();
    await fixture.voice.onTapRecord();
    expect(fixture.captures, 1);
    expect(fixture.voice.recordingOpen, isTrue);
    expect(fixture.voice.busy, isTrue);
    fixture.captureGate.complete(null);
    await first;
    expect(fixture.voice.recordingOpen, isFalse);
  });

  test('late recording after close is deleted without creating a message',
      () async {
    final directory = await Directory.systemTemp.createTemp('voice-module-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/recording.wav').writeAsBytes([1]);
    final pending = fixture.voice.onTapRecord();
    fixture.voice.dispose();
    fixture.captureGate.complete({'path': file.path, 'duration': 4});
    await pending;
    expect(fixture.created, 0);
    expect(fixture.sent, isEmpty);
    expect(await file.exists(), isFalse);
  });
}
