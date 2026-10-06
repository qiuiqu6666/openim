import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/voice/voice_to_text_service.dart';

const _m4a = <int>[
  0,
  0,
  0,
  24,
  102,
  116,
  121,
  112,
  77,
  52,
  65,
  32,
  0,
  0,
  0,
  0,
  77,
  52,
  65,
  32,
  105,
  115,
  111,
  109,
];

Matcher _failure(String key) => throwsA(isA<VoiceToTextException>()
    .having((error) => error.messageKey, 'messageKey', key)
    .having((error) => error.toString(), 'safe error description', key));

void main() {
  late Directory directory;
  final services = <VoiceToTextService>[];

  setUp(() async =>
      directory = await Directory.systemTemp.createTemp('asr-test'));
  tearDown(() async {
    for (final service in services) {
      service.dispose();
    }
    services.clear();
    await directory.delete(recursive: true);
  });

  VoiceToTextService service(
      {Dio? client,
      Dio? downloadClient,
      String? Function()? tokenProvider,
      void Function(String)? logSink}) {
    final value = VoiceToTextService(
      client: client,
      downloadClient: downloadClient,
      endpoint: 'https://chat.example/chat/asr/transcribe',
      tokenProvider: tokenProvider ?? (() => 'chat-token'),
      temporaryDirectory: () async => directory,
      logSink: logSink,
    );
    services.add(value);
    return value;
  }

  Future<File> audio([String name = 'cache', List<int> bytes = _m4a]) async =>
      File('${directory.path}/$name').writeAsBytes(bytes);

  Dio successClient({void Function(RequestOptions)? inspect}) {
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      inspect?.call(request);
      handler.resolve(Response(requestOptions: request, data: {
        'errCode': 0,
        'data': {'text': ' 识别结果 ', 'requestId': 'asr-request'}
      }));
    }));
    return client;
  }

  List<Map<String, dynamic>> events(List<String> lines) => lines
      .map((line) => Map<String, dynamic>.from(jsonDecode(line.substring(6))))
      .toList();

  test('default diagnostics reach Flutter stdout for success and HTTP failure',
      () async {
    final lines = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message?.startsWith('[ASR] ') == true) lines.add(message!);
    };
    addTearDown(() => debugPrint = previousPrint);
    var fail = false;
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (!fail) {
        handler.resolve(Response(requestOptions: request, data: {
          'errCode': 0,
          'data': {'text': 'private recognized words'},
        }));
      } else {
        handler.reject(DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: request, statusCode: 503, data: {
            'errCode': 503,
            'errorCode': 'AUTH_UNAVAILABLE',
            'errMsg': 'private server diagnostic',
          }),
        ));
      }
    }));
    final value =
        service(client: client, tokenProvider: () => 'private-login-token');
    final file = await audio('private-audio-file');
    expect(await value.transcribeFile(file), 'private recognized words');
    expect(events(lines).map((entry) => entry['event']),
        ['start', 'request', 'response', 'success']);
    lines.clear();
    fail = true;
    await expectLater(
        value.transcribeFile(file), _failure('voiceToTextUnavailable'));
    final failure = events(lines).last;
    expect(failure['event'], 'failure');
    expect(failure['httpStatus'], 503);
    expect(failure['errorCode'], 'AUTH_UNAVAILABLE');
    expect(failure['operationID'], isNotEmpty);
    expect(lines.join(), isNot(contains('private-login-token')));
    expect(lines.join(), isNot(contains('private recognized words')));
    expect(lines.join(), isNot(contains('private server diagnostic')));
    expect(lines.join(), isNot(contains('private-audio-file')));
  });

  test('diagnostics correlate proxy failures without logging sensitive data',
      () async {
    const secret = 'private-token-password-signature';
    const requestId = '12345678-abcd-1234-abcd-123456789abc';
    final lines = <String>[];
    final client = Dio();
    late RequestOptions sent;
    var status = 503;
    dynamic body = {
      'errCode': 503,
      'errorCode': 'AUTH_UNAVAILABLE',
      'errMsg': secret,
      'token': secret,
      'data': {'requestId': requestId, 'text': secret},
    };
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      sent = request;
      handler.reject(DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        message: secret,
        response: Response(
          requestOptions: request,
          statusCode: status,
          headers: Headers.fromMap({
            'content-type': [status == 404 ? 'text/html' : 'application/json'],
          }),
          data: body,
        ),
      ));
    }));
    final value = VoiceToTextService(
      client: client,
      endpoint:
          'https://user:$secret@chat.example/chat/asr/transcribe?signature=$secret#$secret',
      tokenProvider: () => secret,
      logSink: lines.add,
    );
    services.add(value);
    final file = await audio('private-audio-name');
    for (final code in ['AUTH_UNAVAILABLE', 'UPSTREAM_ERROR', 'HTML']) {
      lines.clear();
      status = code == 'HTML'
          ? 404
          : code == 'UPSTREAM_ERROR'
              ? 502
              : 503;
      body = code == 'HTML'
          ? '<html>$secret</html>'
          : {
              'errCode': status,
              'errorCode': code,
              'errMsg': secret,
              'data': {'requestId': requestId, 'text': secret},
            };
      await expectLater(value.transcribeFile(file, duration: 7),
          _failure('voiceToTextUnavailable'));
      final entries = events(lines);
      expect(entries.map((entry) => entry['event']),
          ['start', 'request', 'failure']);
      expect(
          entries.every(
              (entry) => entry['operationID'] == sent.headers['operationID']),
          isTrue);
      expect(
          entries[1]['endpoint'], 'https://chat.example/chat/asr/transcribe');
      expect(entries[1]['voiceFormat'], 'm4a');
      expect(entries[1]['audioBytes'], _m4a.length);
      expect(entries.last['httpStatus'], status);
      expect(entries.last['transport'], 'badResponse');
      expect(entries.last['bodyType'], code == 'HTML' ? 'non-json' : 'json');
      if (code != 'HTML') {
        expect(entries.last['errorCode'], code);
        expect(entries.last['requestId'], requestId);
      }
      expect(lines.join(), isNot(contains(secret)));
      expect(lines.join(), isNot(contains('private-audio-name')));
      expect(lines.join(), isNot(contains('<html>')));
    }
    lines.clear();
    status = 502;
    body = {
      'errCode': 502,
      'errorCode': secret,
      'data': {'requestId': secret},
    };
    await expectLater(value.transcribeFile(file, duration: 7),
        _failure('voiceToTextUnavailable'));
    expect(lines.join(), isNot(contains(secret)));
    expect(events(lines).last.containsKey('errorCode'), isFalse);
    expect(events(lines).last.containsKey('requestId'), isFalse);
  });

  test('success logs metadata without recording recognized words', () async {
    final lines = <String>[];
    final value = service(client: successClient(), logSink: lines.add);
    expect(await value.transcribeFile(await audio(), duration: 7), '识别结果');
    final entries = events(lines);
    expect(entries.map((entry) => entry['event']),
        ['start', 'request', 'response', 'success']);
    expect(entries.last['elapsedMs'], isNonNegative);
    expect(lines.join(), isNot(contains('识别结果')));
    expect(entries[2]['errCode'], 0);
  });

  test('validation, timeout and cancellation log their stage safely', () async {
    final lines = <String>[];
    final client = Dio();
    var type = DioExceptionType.receiveTimeout;
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.reject(DioException(
          requestOptions: request,
          type: type,
          message: 'sensitive diagnostic'));
    }));
    final value = service(client: client, logSink: lines.add);
    final file = await audio();
    await expectLater(value.transcribeFile(file, duration: 0),
        _failure('voiceToTextInvalidDuration'));
    expect(events(lines).last['messageKey'], 'voiceToTextInvalidDuration');
    expect(events(lines).last['stage'], 'validate_audio');
    lines.clear();
    await expectLater(
        value.transcribeFile(file), _failure('voiceToTextTimeout'));
    expect(events(lines).last['transport'], 'receiveTimeout');
    lines.clear();
    type = DioExceptionType.cancel;
    await expectLater(value.transcribeFile(file), throwsA(isA<DioException>()));
    expect(events(lines).last['event'], 'cancelled');
    expect(lines.join(), isNot(contains('sensitive diagnostic')));
  });

  test('a failing diagnostic sink cannot break transcription', () async {
    final value = service(
      client: successClient(),
      logSink: (_) => throw StateError('logging unavailable'),
    );
    expect(await value.transcribeFile(await audio()), '识别结果');
  });

  test('remote download logs correlate with upload without exposing signed URL',
      () async {
    final lines = <String>[];
    final downloadClient = Dio();
    downloadClient.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(
        requestOptions: r,
        data: ResponseBody.fromBytes(_m4a, 200),
      ));
    }));
    final value = service(
      client: successClient(),
      downloadClient: downloadClient,
      logSink: lines.add,
    );
    expect(
      await value.transcribeMessage(Message(
        soundElem: SoundElem(
          sourceUrl:
              'https://oss.example/private-file?signature=private-signature',
          duration: 7,
        ),
      )),
      '识别结果',
    );
    final entries = events(lines);
    expect(entries.map((entry) => entry['event']), [
      'start',
      'audio_source',
      'download_start',
      'download_complete',
      'request',
      'response',
      'success',
    ]);
    expect(entries.map((entry) => entry['operationID']).toSet(), hasLength(1));
    expect(entries[3]['audioBytes'], _m4a.length);
    expect(lines.join(), isNot(contains('private-file')));
    expect(lines.join(), isNot(contains('private-signature')));
    expect(await directory.list().toList(), isEmpty);
  });

  test('extensionless M4A uploads a stream with proxy auth and metadata',
      () async {
    final file = await audio();
    late RequestOptions request;
    final client = successClient(inspect: (value) => request = value);
    expect(await service(client: client).transcribeFile(file, duration: 7),
        '识别结果');
    expect(request.path, 'https://chat.example/chat/asr/transcribe');
    expect(request.method, 'POST');
    expect(request.queryParameters, {'voiceFormat': 'm4a', 'duration': 7});
    expect(request.headers['token'], 'chat-token');
    expect(request.headers['operationID'], isNotEmpty);
    expect(request.contentType, 'application/octet-stream');
    expect(request.headers[Headers.contentLengthHeader], _m4a.length);
    expect(request.data, isA<Stream<List<int>>>());
    // An injected interceptor can bypass consuming the body; the body remains
    // file-backed and does not become a buffered List in the request options.
  });

  test('sniff recognizes supported headers and rejects unsupported codecs', () {
    String? sniff(String bytes, [String name = 'cache']) =>
        VoiceToTextService.sniffAudioFormat(bytes.codeUnits, name);
    expect(sniff('RIFF0000WAVEpayload', 'file.mp3'), 'wav');
    expect(sniff('OggS00000OpusHead'), 'ogg-opus');
    expect(sniff('OggS00000Speex '), 'speex');
    expect(sniff('Speex payload'), 'speex');
    expect(sniff('#!SILK_V3'), 'silk');
    expect(sniff('\u0002#!SILK_V3'), 'silk');
    expect(sniff('#!AMR\npayload'), 'amr');
    expect(sniff('#!AMR-WB\npayload'), 'amr');
    expect(sniff('ID3payload'), 'mp3');
    expect(VoiceToTextService.sniffAudioFormat([0xff, 0xfb, 0x90, 0]), 'mp3');
    expect(VoiceToTextService.sniffAudioFormat([0xff, 0xf1, 0x50, 0]), 'aac');
    expect(sniff('raw data', 'file.pcm'), 'pcm');
    expect(sniff('OggS00000vorbis', 'file.ogg'), isNull);
    expect(sniff('fLaCbytes', 'file.mp3'), isNull);
    expect(sniff('random bytes', 'file.m4a'), isNull);
  });

  test(
      'business origin resolves the ASR root path and transfers raw file bytes',
      () async {
    final lines = <String>[];
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    final received = Completer<List<int>>();
    final headers = Completer<Map<String, String?>>();
    final queries = Completer<Map<String, String>>();
    final requestPath = Completer<String>();
    proxy.listen((request) async {
      headers.complete({
        'token': request.headers.value('token'),
        'content-type': request.headers.value('content-type'),
        'operationID': request.headers.value('operationID'),
      });
      queries.complete(request.uri.queryParameters);
      requestPath.complete(request.uri.path);
      received.complete(await request
          .fold<List<int>>([], (buffer, chunk) => buffer..addAll(chunk)));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'errCode': 0,
        'data': {'text': 'wire result', 'requestId': 'wire-request'}
      }));
      await request.response.close();
    });
    final value = VoiceToTextService(
      businessUrl: 'http://127.0.0.1:${proxy.port}/chat/?legacy=value',
      tokenProvider: () => 'wire-token',
      logSink: lines.add,
    );
    services.add(value);
    expect(await value.transcribeFile(await audio(), duration: 12.5),
        'wire result');
    expect(await received.future, _m4a);
    final sentHeaders = await headers.future;
    expect(sentHeaders['token'], 'wire-token');
    expect(sentHeaders['content-type'], 'application/octet-stream');
    expect(sentHeaders['operationID'], isNotEmpty);
    expect(await requestPath.future, '/chat/asr/transcribe');
    expect(await queries.future, {'voiceFormat': 'm4a', 'duration': '12.5'});
    final entries = events(lines);
    expect(entries.where((entry) => entry['event'] == 'upload_complete'),
        hasLength(1));
    expect(entries.last['stage'], 'recognize');
    expect(
        entries.every(
            (entry) => entry['operationID'] == sentHeaders['operationID']),
        isTrue);
  });

  test(
      'size, duration, format, empty audio and authentication fail before upload',
      () async {
    var requests = 0;
    final value = service(client: successClient(inspect: (_) => requests++));
    final file = await audio();
    for (final duration in [
      0,
      -1,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      await expectLater(value.transcribeFile(file, duration: duration),
          _failure('voiceToTextInvalidDuration'));
    }
    await expectLater(
        value.transcribeMessage(
            Message(soundElem: SoundElem(soundPath: file.path, duration: -1))),
        _failure('voiceToTextInvalidDuration'));
    await expectLater(value.transcribeFile(file, duration: 7200.1),
        _failure('voiceToTextTooLong'));
    await expectLater(
        value.transcribeFile(await audio('fake.mp3', [1, 2, 3]), duration: 2),
        _failure('voiceToTextUnsupportedFormat'));
    await expectLater(
        value.transcribeFile(await audio('empty', []), duration: 2),
        _failure('voiceToTextMissingAudio'));
    final large = await audio('large');
    final handle = await large.open(mode: FileMode.write);
    await handle.truncate(VoiceToTextService.maxAudioBytes + 1);
    await handle.close();
    await expectLater(value.transcribeFile(large, duration: 2),
        _failure('voiceToTextTooLarge'));
    await expectLater(
        service(client: successClient(), tokenProvider: () => null)
            .transcribeFile(file, duration: 2),
        _failure('voiceToTextAuthFailed'));
    expect(requests, 0);
  });

  test(
      'unknown file and historical message durations are omitted from requests',
      () async {
    final requests = <RequestOptions>[];
    final value = service(client: successClient(inspect: requests.add));
    final file = await audio();
    expect(await value.transcribeFile(file), '识别结果');
    for (final duration in [null, 0]) {
      expect(
          await value.transcribeMessage(Message(
              soundElem: SoundElem(soundPath: file.path, duration: duration))),
          '识别结果');
    }
    expect(requests, hasLength(3));
    for (final request in requests) {
      expect(request.queryParameters, {'voiceFormat': 'm4a'});
      expect(request.contentType, 'application/octet-stream');
      expect(request.headers['token'], 'chat-token');
      expect(request.data, isA<Stream<List<int>>>());
    }
  });

  test('existing message audio uses local path before its remote URL',
      () async {
    var downloads = 0;
    final downloadClient = Dio();
    downloadClient.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      downloads++;
      h.reject(DioException(requestOptions: r));
    }));
    final file = await audio();
    final message = Message(
        clientMsgID: 'voice',
        soundElem: SoundElem(
            soundPath: file.path,
            sourceUrl: 'https://oss.example/audio',
            duration: 5));
    expect(
        await service(client: successClient(), downloadClient: downloadClient)
            .transcribeMessage(message),
        '识别结果');
    expect(downloads, 0);
    expect(await file.exists(), isTrue);
  });

  test('remote fallback streams without token and removes its temporary audio',
      () async {
    late RequestOptions remoteRequest;
    final downloadClient = Dio(BaseOptions(
        headers: {'Token': 'must-not-leak', 'Authorization': 'must-not-leak'}));
    downloadClient.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      remoteRequest = r;
      h.resolve(Response(
          requestOptions: r,
          data: ResponseBody(Stream.value(Uint8List.fromList(_m4a)), 200)));
    }));
    final message = Message(
        clientMsgID: 'voice',
        soundElem: SoundElem(
            soundPath: '${directory.path}/gone',
            sourceUrl: 'https://oss.example/no-extension',
            duration: 5));
    expect(
        await service(client: successClient(), downloadClient: downloadClient)
            .transcribeMessage(message),
        '识别结果');
    expect(remoteRequest.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('token')));
    expect(remoteRequest.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')));
    expect(await directory.list().toList(), isEmpty);
  });

  test('failed remote downloads clean files and can be retried', () async {
    var attempts = 0;
    final downloadClient = Dio();
    downloadClient.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      attempts++;
      if (attempts == 1) {
        h.reject(DioException(
            requestOptions: r, type: DioExceptionType.connectionError));
      } else {
        h.resolve(Response(
            requestOptions: r,
            data: ResponseBody(Stream.value(Uint8List.fromList(_m4a)), 200)));
      }
    }));
    final value =
        service(client: successClient(), downloadClient: downloadClient);
    final message = Message(
        soundElem:
            SoundElem(sourceUrl: 'https://oss.example/audio', duration: 5));
    await expectLater(
        value.transcribeMessage(message), _failure('voiceToTextNetworkFailed'));
    expect(await directory.list().toList(), isEmpty);
    expect(await value.transcribeMessage(message), '识别结果');
    expect(attempts, 2);
    expect(await directory.list().toList(), isEmpty);
  });

  test('advertised download size is checked before writing bytes', () async {
    final downloadClient = Dio();
    downloadClient.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(
          requestOptions: r,
          data: ResponseBody(Stream.value(Uint8List.fromList(_m4a)), 200,
              headers: {
                Headers.contentLengthHeader: [
                  '${VoiceToTextService.maxAudioBytes + 1}'
                ]
              })));
    }));
    await expectLater(
        service(client: successClient(), downloadClient: downloadClient)
            .transcribeMessage(Message(
                soundElem: SoundElem(
                    sourceUrl: 'https://oss.example/audio', duration: 5))),
        _failure('voiceToTextTooLarge'));
    expect(await directory.list().toList(), isEmpty);
  });

  test('cancelling a stalled download closes its stream and removes the file',
      () async {
    final stream = StreamController<Uint8List>();
    final started = Completer<void>();
    final downloadClient = Dio();
    downloadClient.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(
          Response(requestOptions: r, data: ResponseBody(stream.stream, 200)));
      started.complete();
    }));
    final token = CancelToken();
    final result =
        service(client: successClient(), downloadClient: downloadClient)
            .transcribeMessage(
                Message(
                    soundElem: SoundElem(
                        sourceUrl: 'https://oss.example/audio', duration: 5)),
                cancelToken: token);
    final assertion = expectLater(
        result,
        throwsA(isA<DioException>()
            .having(CancelToken.isCancel, 'cancelled', isTrue)));
    await started.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel();
    await assertion;
    expect(await directory.list().toList(), isEmpty);
    await stream.close();
  });

  test('streamed downloads enforce the limit without a content-length header',
      () async {
    final downloadClient = Dio();
    final chunk = Uint8List(4 * 1024 * 1024);
    downloadClient.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(
        requestOptions: r,
        data: ResponseBody(
            Stream.fromIterable(List<Uint8List>.filled(26, chunk)), 200),
      ));
    }));
    var uploads = 0;
    await expectLater(
        service(
                client: successClient(inspect: (_) => uploads++),
                downloadClient: downloadClient)
            .transcribeMessage(Message(
                soundElem: SoundElem(
                    sourceUrl: 'https://oss.example/audio', duration: 5))),
        _failure('voiceToTextTooLarge'));
    expect(uploads, 0);
    expect(await directory.list().toList(), isEmpty);
  });

  test('provider failures and empty recognition return safe localized errors',
      () async {
    final client = Dio();
    dynamic body = {
      'errCode': 1,
      'errorCode': 'UNKNOWN_PROVIDER_CODE',
      'errMsg': 'secret diagnostic',
    };
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.resolve(Response(requestOptions: r, data: body));
    }));
    final value = service(client: client);
    final file = await audio();
    await expectLater(
        value.transcribeFile(file, duration: 5), _failure('voiceToTextFailed'));
    body = {
      'errCode': 429,
      'errorCode': 'RATE_LIMITED',
      'errMsg': 'secret diagnostic',
    };
    await expectLater(value.transcribeFile(file, duration: 5),
        _failure('voiceToTextRateLimited'));
    body = {
      'errCode': 0,
      'data': {'text': '  '}
    };
    await expectLater(
        value.transcribeFile(file, duration: 5), _failure('voiceToTextEmpty'));
    body = jsonEncode({'errCode': 0}); // A malformed body is never success.
    await expectLater(
        value.transcribeFile(file, duration: 5), _failure('voiceToTextFailed'));
  });

  test('proxy HTTP contract translates numeric errCode and stable errorCode',
      () async {
    const cases = [
      (400, 'BAD_REQUEST', 'voiceToTextFailed'),
      (400, 'BAD_FORMAT', 'voiceToTextUnsupportedFormat'),
      (400, 'BAD_DURATION', 'voiceToTextInvalidDuration'),
      (400, 'EMPTY_AUDIO', 'voiceToTextMissingAudio'),
      (400, 'UNKNOWN_PARAM', 'voiceToTextFailed'),
      (401, 'AUTH_INVALID_TOKEN', 'voiceToTextAuthFailed'),
      (413, 'PAYLOAD_TOO_LARGE', 'voiceToTextTooLarge'),
      (415, 'UNSUPPORTED_MEDIA', 'voiceToTextUnsupportedFormat'),
      (422, 'NO_SPEECH', 'voiceToTextEmpty'),
      (422, 'AUDIO_TOO_LONG', 'voiceToTextTooLong'),
      (429, 'RATE_LIMITED', 'voiceToTextRateLimited'),
      (502, 'UPSTREAM_ERROR', 'voiceToTextUnavailable'),
      (503, 'AUTH_UNAVAILABLE', 'voiceToTextUnavailable'),
      (504, 'TIMEOUT', 'voiceToTextTimeout'),
    ];
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    var current = cases.first;
    var requests = 0;
    proxy.listen((request) async {
      await request.drain<void>();
      requests++;
      request.response.statusCode = current.$1;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'errCode': current.$1,
        'errorCode': current.$2,
        'errMsg': 'provider diagnostic; token=private; signature=private',
        'secretKey': 'must not display',
        'data': {'requestId': 'provider-request'},
      }));
      await request.response.close();
    });
    final value = VoiceToTextService(
      endpoint: 'http://127.0.0.1:${proxy.port}/chat/asr/transcribe',
      tokenProvider: () => 'wire-token',
    );
    services.add(value);
    final file = await audio();
    for (final failure in cases) {
      current = failure;
      await expectLater(
          value.transcribeFile(file, duration: 5), _failure(failure.$3),
          reason: 'HTTP ${failure.$1} / ${failure.$2}');
    }
    expect(requests, cases.length);
  });

  test('stable errorCode takes precedence while older proxy aliases still work',
      () async {
    final client = Dio();
    dynamic body;
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.reject(DioException(
        requestOptions: r,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: r, statusCode: 422, data: body),
      ));
    }));
    final value = service(client: client);
    final file = await audio();
    const aliases = {
      'AUDIO_TOO_LARGE': 'voiceToTextTooLarge',
      'UNSUPPORTED_AUDIO_FORMAT': 'voiceToTextUnsupportedFormat',
      'AUDIO_DECODE_FAILED': 'voiceToTextUnsupportedFormat',
    };
    for (final entry in aliases.entries) {
      for (final field in ['errorCode', 'errCode']) {
        body = {
          field: entry.key,
          'errMsg': 'must not display sensitive provider details',
        };
        await expectLater(
            value.transcribeFile(file, duration: 5), _failure(entry.value));
      }
    }
    body = {
      'errorCode': 'RATE_LIMITED',
      'errCode': 'AUDIO_TOO_LARGE',
      'errMsg': 'private provider diagnostic',
    };
    await expectLater(value.transcribeFile(file, duration: 5),
        _failure('voiceToTextRateLimited'));
    body = {
      'errorCode': 'unknown private provider detail',
      'errCode': 'AUDIO_TOO_LARGE',
      'errMsg': 'private token and signature',
    };
    await expectLater(value.transcribeFile(file, duration: 5),
        _failure('voiceToTextNetworkFailed'));
  });

  test('HTTP status safely handles errors without recognized proxy codes',
      () async {
    final client = Dio();
    var status = 400;
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.reject(DioException(
        requestOptions: r,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: r,
          statusCode: status,
          // Gateways may return HTML instead of the proxy JSON contract.
          data: '<html>private upstream diagnostic and token</html>',
        ),
      ));
    }));
    final value = service(client: client);
    final file = await audio();
    const cases = {
      400: 'voiceToTextFailed',
      401: 'voiceToTextAuthFailed',
      403: 'voiceToTextAuthFailed',
      413: 'voiceToTextTooLarge',
      415: 'voiceToTextUnsupportedFormat',
      429: 'voiceToTextRateLimited',
      404: 'voiceToTextUnavailable',
      502: 'voiceToTextUnavailable',
      503: 'voiceToTextUnavailable',
      504: 'voiceToTextTimeout',
      422: 'voiceToTextNetworkFailed',
      500: 'voiceToTextNetworkFailed',
    };
    for (final entry in cases.entries) {
      status = entry.key;
      await expectLater(
          value.transcribeFile(file, duration: 5), _failure(entry.value));
    }
  });

  test('connection, upload and recognition timeouts have a dedicated error',
      () async {
    final client = Dio();
    var type = DioExceptionType.connectionTimeout;
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      h.reject(DioException(
        requestOptions: r,
        type: type,
        message: 'private URL, token and provider diagnostic',
      ));
    }));
    final value = service(client: client);
    final file = await audio();
    for (final timeout in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      type = timeout;
      await expectLater(value.transcribeFile(file, duration: 5),
          _failure('voiceToTextTimeout'));
    }
  });

  test('dispose cancels active uploads and prevents new requests', () async {
    final started = Completer<void>();
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r, h) async {
      started.complete();
      final error = await r.cancelToken!.whenCancel;
      h.reject(error);
    }));
    final value = service(client: client);
    final file = await audio();
    final request = value.transcribeFile(file, duration: 5);
    final assertion = expectLater(
        request,
        throwsA(isA<DioException>()
            .having(CancelToken.isCancel, 'cancelled', isTrue)));
    await started.future;
    value.dispose();
    await assertion;
    await expectLater(
        value.transcribeFile(file, duration: 5),
        throwsA(isA<DioException>()
            .having(CancelToken.isCancel, 'cancelled', isTrue)));
  });
}
