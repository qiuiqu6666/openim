import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/voice/voice_to_text_service.dart';
import 'package:openim/pages/chat/voice/voice_transcription_controller.dart';

void main() {
  Message message([String id = 'voice']) => Message(
      clientMsgID: id,
      contentType: MessageType.voice,
      localEx: '{"voiceHeard":false,"unrelated":42}',
      isRead: false,
      soundElem: SoundElem(duration: 4));

  Message privateMessage({int? readTime, int burnDuration = 1}) => message()
    ..attachedInfoElem = AttachedInfoElem(
      isPrivateChat: true,
      hasReadTime: readTime,
      burnDuration: burnDuration,
    );

  test('cached successful text is hydrated and toggles without recognition',
      () async {
    var requests = 0;
    final value = message()
      ..localEx = jsonEncode({
        'voiceToText': 'saved words',
        'voiceToTextDisplayState': 'collapsed',
        'voiceHeard': true,
      });
    final controller = VoiceTranscriptionController(
        transcribe: (Message _, {CancelToken? cancelToken}) async {
      requests++;
      return 'new words';
    });
    addTearDown(controller.dispose);
    expect(controller.stateFor(value).text, 'saved words');
    expect(controller.stateFor(value).expanded, isFalse);
    await controller.transcribe(value);
    await controller.toggle(value);
    expect(requests, 0);
    expect(controller.stateFor(value).expanded, isTrue);
    expect(jsonDecode(value.localEx!)['voiceHeard'], isTrue);
    expect(jsonDecode(value.localEx!)['voiceToTextDisplayState'], 'expanded');
  });

  test('repeated message taps share a job and preserve fresh localEx fields',
      () async {
    var requests = 0;
    final answer = Completer<String>();
    final value = message();
    final controller = VoiceTranscriptionController(
        transcribe: (Message _, {CancelToken? cancelToken}) {
      requests++;
      return answer.future;
    });
    addTearDown(controller.dispose);
    final first = controller.transcribe(value);
    final second = controller.transcribe(value);
    expect(identical(first, second), isTrue);
    expect(controller.stateFor(value).loading, isTrue);
    await Future<void>.delayed(Duration.zero);
    value.localEx = '{"voiceHeard":true,"unrelated":43}';
    answer.complete(' result ');
    await first;
    expect(requests, 1);
    expect(controller.stateFor(value).text, 'result');
    expect(controller.stateFor(value).loading, isFalse);
    expect(jsonDecode(value.localEx!), {
      'voiceHeard': true,
      'unrelated': 43,
      'voiceToText': 'result',
      'voiceToTextDisplayState': 'expanded',
    });
    expect(value.isRead, isFalse);
  });

  test('persistence callback receives only a patch for the shared writer',
      () async {
    final writes = <Map<String, dynamic>>[];
    final answer = Completer<String>();
    final value = message();
    final controller = VoiceTranscriptionController(
      transcribe: (Message _, {CancelToken? cancelToken}) => answer.future,
      persist: (item, patch) async {
        writes.add(patch);
        // This emulates the conversation writer's merge at execution time.
        item.localEx = jsonEncode(
            Map<String, dynamic>.from(jsonDecode(item.localEx!))
              ..addAll(patch));
      },
    );
    addTearDown(controller.dispose);
    final running = controller.transcribe(value);
    value.localEx = '{"voiceHeard":true,"concurrent":"preserved"}';
    answer.complete('words');
    await running;
    expect(writes.single, {
      'voiceToText': 'words',
      'voiceToTextDisplayState': 'expanded',
    });
    expect(jsonDecode(value.localEx!)['voiceHeard'], isTrue);
    await controller.toggle(value);
    expect(writes.last['voiceToTextDisplayState'], 'collapsed');
    expect(jsonDecode(value.localEx!)['concurrent'], 'preserved');
  });

  test('failure exposes a safe error and retry recognizes successfully',
      () async {
    var requests = 0;
    final value = message();
    final controller = VoiceTranscriptionController(
        transcribe: (Message _, {CancelToken? cancelToken}) async {
      if (++requests == 1) {
        throw const VoiceToTextException('voiceToTextNetworkFailed');
      }
      return 'retry succeeded';
    });
    addTearDown(controller.dispose);
    await controller.transcribe(value);
    expect(controller.stateFor(value).error, 'voiceToTextNetworkFailed');
    expect(controller.stateFor(value).hasText, isFalse);
    expect(jsonDecode(value.localEx!).containsKey('voiceToText'), isFalse);
    await controller.transcribe(value);
    expect(requests, 2);
    expect(controller.stateFor(value).text, 'retry succeeded');
    expect(controller.stateFor(value).error, isNull);
  });

  test('different messages can transcribe concurrently', () async {
    final answers = <String, Completer<String>>{};
    final controller = VoiceTranscriptionController(
        transcribe: (Message value, {CancelToken? cancelToken}) =>
            (answers[value.clientMsgID!] = Completer<String>()).future);
    addTearDown(controller.dispose);
    final first = message('first');
    final second = message('second');
    final firstJob = controller.transcribe(first);
    final secondJob = controller.transcribe(second);
    await Future<void>.delayed(Duration.zero);
    expect(answers.keys, containsAll(['first', 'second']));
    answers['second']!.complete('second text');
    await secondJob;
    expect(controller.stateFor(first).loading, isTrue);
    expect(controller.stateFor(second).text, 'second text');
    answers['first']!.complete('first text');
    await firstJob;
  });

  test('deleted message cancels its job and ignores a late result', () async {
    final answer = Completer<String>();
    CancelToken? token;
    var writes = 0;
    final value = message();
    final controller = VoiceTranscriptionController(
      transcribe: (Message _, {CancelToken? cancelToken}) {
        token = cancelToken;
        return answer.future;
      },
      persist: (_, __) async => writes++,
    );
    addTearDown(controller.dispose);
    final running = controller.transcribe(value);
    await Future<void>.delayed(Duration.zero);
    controller.remove('voice');
    expect(token!.isCancelled, isTrue);
    answer.complete('late text');
    await running;
    expect(writes, 0);
    expect(controller.stateFor(value).hasText, isFalse);
    expect(controller.stateFor(value).loading, isFalse);
  });

  test('disposing cancels outstanding jobs and prevents late notifications',
      () async {
    final answer = Completer<String>();
    CancelToken? token;
    var notifications = 0;
    var writes = 0;
    final value = message();
    final controller = VoiceTranscriptionController(
      transcribe: (Message _, {CancelToken? cancelToken}) {
        token = cancelToken;
        return answer.future;
      },
      persist: (_, __) async => writes++,
    )..addListener(() => notifications++);
    final running = controller.transcribe(value);
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    controller.dispose();
    expect(token!.isCancelled, isTrue);
    answer.complete('late text');
    await running;
    expect(writes, 0);
    expect(notifications, 1);
    await controller.transcribe(value);
  });

  test('malformed persisted state can be recognized and does not mark read',
      () async {
    final value = message()..localEx = 'not json';
    final controller = VoiceTranscriptionController(
        transcribe: (Message _, {CancelToken? cancelToken}) async =>
            'valid words');
    addTearDown(controller.dispose);
    await controller.toggle(value);
    expect(controller.stateFor(value).text, 'valid words');
    expect(value.isRead, isFalse);
  });

  test(
      'only valid voice messages, including unread private voice, can transcribe',
      () {
    final now = DateTime(2026, 10, 3);
    final controller = VoiceTranscriptionController(
      now: () => now,
      transcribe: (Message _, {CancelToken? cancelToken}) async => 'words',
    );
    addTearDown(controller.dispose);
    expect(controller.canTranscribe(message()), isTrue);
    expect(controller.canTranscribe(privateMessage()), isTrue);
    expect(controller.canTranscribe(message()..soundElem = null), isFalse);
    expect(controller.canTranscribe(message()..contentType = MessageType.text),
        isFalse);
    expect(
        controller.canTranscribe(privateMessage(
            readTime: now
                .subtract(const Duration(seconds: 1))
                .millisecondsSinceEpoch)),
        isFalse);
  });

  test('private recognition and toggling stay in memory and ignore local cache',
      () async {
    var requests = 0;
    var writes = 0;
    final value = privateMessage()
      ..localEx = jsonEncode({
        'voiceHeard': true,
        'voiceToText': 'old private cache',
        'voiceToTextDisplayState': 'collapsed',
      });
    final original = value.localEx;
    final controller = VoiceTranscriptionController(
      transcribe: (Message _, {CancelToken? cancelToken}) async {
        requests++;
        return 'private words';
      },
      persist: (_, __) async => writes++,
    );
    addTearDown(controller.dispose);
    expect(controller.stateFor(value).hasText, isFalse);
    await controller.transcribe(value);
    expect(controller.stateFor(value).text, 'private words');
    expect(controller.stateFor(value).expanded, isTrue);
    await controller.toggle(value);
    expect(controller.stateFor(value).expanded, isFalse);
    await controller.toggle(value);
    expect(controller.stateFor(value).expanded, isTrue);
    expect(requests, 1);
    expect(writes, 0);
    expect(value.localEx, original);
  });

  test(
      'private recognition never changes localEx without a persistence callback',
      () async {
    final value = privateMessage();
    final original = value.localEx;
    final controller = VoiceTranscriptionController(
      transcribe: (Message _, {CancelToken? cancelToken}) async =>
          'private words',
    );
    addTearDown(controller.dispose);
    await controller.transcribe(value);
    await controller.toggle(value);
    expect(controller.stateFor(value).text, 'private words');
    expect(value.localEx, original);
  });

  testWidgets('private expiry cancels recognition and discards a late result',
      (tester) async {
    var now = DateTime(2026, 10, 3);
    final value = privateMessage(readTime: now.millisecondsSinceEpoch);
    final answer = Completer<String>();
    CancelToken? token;
    var writes = 0;
    final controller = VoiceTranscriptionController(
      now: () => now,
      transcribe: (Message _, {CancelToken? cancelToken}) {
        token = cancelToken;
        return answer.future;
      },
      persist: (_, __) async => writes++,
    );
    addTearDown(controller.dispose);
    final running = controller.transcribe(value);
    await tester.pump();
    expect(controller.stateFor(value).loading, isTrue);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(token!.isCancelled, isTrue);
    expect(controller.stateFor(value).loading, isFalse);
    answer.complete('late private words');
    await running;
    expect(controller.stateFor(value).hasText, isFalse);
    expect(writes, 0);
  });

  testWidgets('private transcript is removed when its read deadline appears',
      (tester) async {
    var now = DateTime(2026, 10, 3);
    final value = privateMessage();
    final controller = VoiceTranscriptionController(
      now: () => now,
      transcribe: (Message _, {CancelToken? cancelToken}) async =>
          'private words',
    );
    addTearDown(controller.dispose);
    await controller.transcribe(value);
    expect(controller.stateFor(value).text, 'private words');
    value.attachedInfoElem!.hasReadTime = now.millisecondsSinceEpoch;
    // Toggling observes the newly established deadline.
    await controller.toggle(value);
    expect(controller.stateFor(value).expanded, isFalse);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.stateFor(value).hasText, isFalse);
  });

  testWidgets('stateFor follows a replacement message with a changed deadline',
      (tester) async {
    var now = DateTime(2026, 10, 3);
    final original = privateMessage(readTime: now.millisecondsSinceEpoch);
    final controller = VoiceTranscriptionController(
      now: () => now,
      transcribe: (Message _, {CancelToken? cancelToken}) async =>
          'private words',
    );
    addTearDown(controller.dispose);
    await controller.transcribe(original);
    final replacement =
        privateMessage(readTime: now.millisecondsSinceEpoch, burnDuration: 3);
    expect(controller.stateFor(replacement).hasText, isTrue);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.stateFor(replacement).hasText, isTrue);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.stateFor(replacement).hasText, isFalse);
  });

  testWidgets('late private error after expiry is not displayed',
      (tester) async {
    var now = DateTime(2026, 10, 3);
    final value = privateMessage(readTime: now.millisecondsSinceEpoch);
    final answer = Completer<String>();
    final controller = VoiceTranscriptionController(
      now: () => now,
      transcribe: (Message _, {CancelToken? cancelToken}) => answer.future,
    );
    addTearDown(controller.dispose);
    final running = controller.transcribe(value);
    await tester.pump();
    now = now.add(const Duration(seconds: 2));
    // Check expiry at completion even before the timer can run.
    answer
        .completeError(const VoiceToTextException('voiceToTextNetworkFailed'));
    await running;
    expect(controller.stateFor(value).error, isNull);
    expect(controller.stateFor(value).loading, isFalse);
    await tester.pump(const Duration(seconds: 2));
  });

  test('expired stateFor clears privately without notifying during build',
      () async {
    var now = DateTime(2026, 10, 3);
    final value = privateMessage(readTime: now.millisecondsSinceEpoch);
    final controller = VoiceTranscriptionController(
      now: () => now,
      transcribe: (Message _, {CancelToken? cancelToken}) async =>
          'private words',
    );
    addTearDown(controller.dispose);
    await controller.transcribe(value);
    var notifications = 0;
    controller.addListener(() => notifications++);
    now = now.add(const Duration(seconds: 1));
    expect(controller.stateFor(value).hasText, isFalse);
    expect(notifications, 0);
    await controller.toggle(value);
    expect(controller.stateFor(value).hasText, isFalse);
  });

  testWidgets('removing private message clears its timer and pending job',
      (tester) async {
    var now = DateTime(2026, 10, 3);
    final value = privateMessage(readTime: now.millisecondsSinceEpoch);
    final answer = Completer<String>();
    CancelToken? token;
    final controller = VoiceTranscriptionController(
      now: () => now,
      transcribe: (Message _, {CancelToken? cancelToken}) {
        token = cancelToken;
        return answer.future;
      },
    );
    addTearDown(controller.dispose);
    final running = controller.transcribe(value);
    await tester.pump();
    controller.remove(value.clientMsgID!);
    expect(token!.isCancelled, isTrue);
    var notifications = 0;
    controller.addListener(() => notifications++);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    answer.complete('deleted words');
    await running;
    expect(controller.stateFor(value).hasText, isFalse);
    expect(notifications, 0);
  });

  testWidgets(
      'disposing private controller clears expiry timers and cached text',
      (tester) async {
    var now = DateTime(2026, 10, 3);
    final value = privateMessage(readTime: now.millisecondsSinceEpoch);
    final controller = VoiceTranscriptionController(
      now: () => now,
      transcribe: (Message _, {CancelToken? cancelToken}) async =>
          'private words',
    );
    await controller.transcribe(value);
    expect(controller.stateFor(value).hasText, isTrue);
    controller.dispose();
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.stateFor(value).hasText, isFalse);
    await controller.transcribe(value);
  });
}
