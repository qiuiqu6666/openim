import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_openim_sdk/src/diagnostics/media_diagnostic_journal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('media-log-test');
  final calls = <MethodCall>[];
  late Directory directory;
  Object? uploadError;
  Object? logError;

  Future<IMManager> manager() async {
    final result = IMManager(channel);
    await result.init(
        InitConfig(
            platformID: 1, apiAddr: '', wsAddr: '', dataDir: directory.path),
        OnConnectListener());
    return result;
  }

  setUp(() async {
    calls.clear();
    uploadError = logError = null;
    directory = await Directory.systemTemp.createTemp('media-diagnostics-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'logs') {
        expect(call.arguments['ManagerName'], 'imManager');
      }
      if (call.method == 'logs' && logError != null) throw logError!;
      if (call.method == 'initSDK') return true;
      if (call.method == 'uploadFile') {
        if (uploadError != null) throw uploadError!;
        return '{"url":"https://media.test/file"}';
      }
      if (call.method == 'sendMessage' || call.method == 'sendMessageNotOss') {
        return jsonEncode(
            {'clientMsgID': 'msg-1', 'status': MessageStatus.succeeded});
      }
      return null;
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test(
      'failed video upload survives restart and is replayed before tail export',
      () async {
    var sdk = await manager();
    uploadError = PlatformException(
        code: '10017',
        message:
            'Put https://cos.test/private?token=secret: context deadline exceeded');
    await expectLater(
        sdk.uploadFile(
            id: 'chat-media:msg-1',
            filePath: '/private/video.mp4',
            fileName: 'private.mp4',
            contentType: 'video/mp4',
            operationID: 'attempt-1'),
        throwsA(isA<PlatformException>()));
    // Await the disk queue via the export barrier before simulating a restart.
    await sdk.uploadLogs(line: 10);
    sdk = await manager();
    calls.clear();
    await sdk.uploadLogs(
        line: 1, ex: '{"feedbackID":"fb_test"}', operationID: 'export-2');
    final snapshotCall = calls.firstWhere((c) =>
        c.method == 'logs' &&
        (c.arguments['msgs'] as String).startsWith('chat_media_snapshot '));
    final text = snapshotCall.arguments['msgs'] as String;
    final snapshot = jsonDecode(text.substring('chat_media_snapshot '.length));
    final events = snapshot['events'] as List;
    expect(events.map((e) => e['outcome']), ['start', 'failed']);
    expect(events.last['failureReason'], 'timeout');
    expect(events.last['traceID'], 'attempt-1');
    expect(events.last['clientMsgID'], 'msg-1');
    expect(events.last['mediaType'], 'video');
    expect(events.last['timestampUtc'], endsWith('Z'));
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('private')));
    expect(calls.last.method, 'uploadLogs');
    expect(calls.last.arguments['line'], 100);
    expect(calls.last.arguments['ex'], '{"feedbackID":"fb_test"}');
  });

  test(
      'both media send APIs record start and completion without message contents',
      () async {
    final sdk = await manager();
    final message = Message(exMap: {})
      ..clientMsgID = 'msg-1'
      ..contentType = MessageType.picture
      ..ex = 'private message body';
    await sdk.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        operationID: 'send-1');
    message.contentType = MessageType.video;
    await sdk.messageManager.sendMessageNotOss(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        operationID: 'send-2');
    await sdk.uploadLogs();
    final snapshot =
        calls.where((c) => c.method == 'logs').last.arguments['msgs'] as String;
    expect(snapshot, contains('sdk_send_uploaded'));
    expect(snapshot, contains('sdk_send'));
    expect(snapshot, contains('"outcome":"complete"'));
    expect(snapshot, isNot(contains('private message body')));
  });

  test('diagnostic bridge failure does not fail a media send', () async {
    final sdk = await manager();
    logError = PlatformException(code: 'logger_unavailable');
    final result = await sdk.messageManager.sendMessage(
        message: Message(exMap: {})..contentType = MessageType.video,
        offlinePushInfo: OfflinePushInfo());
    expect(result.status, MessageStatus.succeeded);
    logError = null;
    await sdk.uploadLogs();
  });

  test('export refuses to silently omit the media snapshot', () async {
    final sdk = await manager();
    await sdk.uploadFile(
        id: 'chat-media:msg-1',
        filePath: '/private/image.jpg',
        fileName: 'image.jpg',
        contentType: 'image/jpeg');
    logError = PlatformException(code: 'logger_unavailable');
    await expectLater(
        sdk.uploadLogs(line: 1), throwsA(isA<PlatformException>()));
    expect(calls.where((c) => c.method == 'uploadLogs'), isEmpty);
  });

  test('COS error extracts status and request ID without signed URL', () {
    final fields = mediaErrorFields(PlatformException(
        code: '10017',
        message: 'StatusCode: 403, Code: SignatureDoesNotMatch, '
            'RequestID: abcdef1234567890 Put https://cos.test/private?token=secret'));
    expect(fields, {
      'failureReason': 'signature_mismatch',
      'httpStatus': 403,
      'requestID': 'abcdef1234567890',
      'cosCode': 'SignatureDoesNotMatch',
    });
  });

  test('bounded journal tolerates a broken trailing record and filters fields',
      () async {
    final journal = MediaDiagnosticJournal()..configure(directory.path);
    for (var i = 0; i < 520; i++) {
      journal.capture('chat_media ${jsonEncode({
            'stage': 'upload_source',
            'count': i,
            'url': 'https://private.test',
            'traceID': 'bad/url?token=secret',
          })}');
    }
    final events = await journal.snapshot();
    expect(events.length, MediaDiagnosticJournal.capacity);
    expect(events.first['count'], 8);
    await File('${directory.path}/media-diagnostics.jsonl')
        .writeAsString('{broken', mode: FileMode.append);
    final restarted = MediaDiagnosticJournal()..configure(directory.path);
    final restored = await restarted.snapshot();
    expect(restored.length, MediaDiagnosticJournal.capacity);
    expect(jsonEncode(restored), isNot(contains('secret')));
    expect(jsonEncode(restored), isNot(contains('private.test')));
  });
}
