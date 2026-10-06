import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/device_sync/data/device_sync_api.dart';

final _now = DateTime.utc(2026, 10, 5, 12);
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _device = DeviceSyncDevice(
    deviceID: 'login-device-1', deviceName: 'Test phone', platform: 'Android');
const _oss =
    'https://99chat.oss-cn-hongkong.aliyuncs.com/media/file?signature=private';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions, Stream<Uint8List>?)
      respond;
  final requests = <RequestOptions>[];
  int closes = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return await respond(options, stream);
  }

  @override
  void close({bool force = false}) => closes++;
}

Dio _dio(_Adapter adapter) => Dio()..httpClientAdapter = adapter;
ResponseBody _response(Object? data, {int code = 0, int status = 200}) =>
    ResponseBody.fromString(
        jsonEncode({
          'errCode': code,
          'errMsg': 'private-token $_oss',
          'errDlt': 'private stack',
          'data': data
        }),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
DeviceSyncMedia _media(
        {String id = 'photo-1',
        int size = 5,
        DeviceSyncMediaKind kind = DeviceSyncMediaKind.image,
        String? type}) =>
    DeviceSyncMedia(
        localID: id,
        sha256: _hash,
        size: size,
        kind: kind,
        name: 'folder/IMG.jpg',
        contentType: type);
Map<String, dynamic> _probe(DeviceSyncMedia media, {String state = 'upload'}) =>
    {
      'localID': media.localID,
      'state': state,
      'received': state == 'done' ? media.size : 0,
      'reset': false,
      'mode': '',
      'partSize': 0,
      'doneParts': []
    };
Map<String, dynamic> _put(DeviceSyncMedia media) => {
      'mode': 'put',
      'state': 'upload',
      'url': _oss,
      'contentType': media.contentType,
      'expiresAt': _now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
      'partSize': media.size,
      'size': media.size,
      'uploadID': '',
      'received': 0,
      'parts': [],
      'doneParts': []
    };
Map<String, dynamic> _multipart(DeviceSyncMedia media) {
  final count = (media.size + deviceSyncPartSize - 1) ~/ deviceSyncPartSize;
  return {
    'mode': 'multipart',
    'state': 'resume',
    'url': '',
    'contentType': media.contentType,
    'expiresAt': _now.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
    'partSize': deviceSyncPartSize,
    'size': media.size,
    'uploadID': 'upload-1',
    'received': deviceSyncPartSize,
    'doneParts': [1],
    'parts': [
      for (var number = 2; number <= count; number++)
        {
          'partNumber': number,
          'offset': (number - 1) * deviceSyncPartSize,
          'size': number == count
              ? media.size - (number - 1) * deviceSyncPartSize
              : deviceSyncPartSize,
          'url': '$_oss&partNumber=$number',
        }
    ]
  };
}

DeviceSyncApi _api(_Adapter chat,
        {_Adapter? upload,
        bool Function()? isCurrent,
        DateTime Function()? now}) =>
    DeviceSyncApi(
        device: _device,
        chatToken: 'captured-chat-token',
        baseUrl: 'https://chat.test/chat/',
        client: _dio(chat),
        uploadClient: upload == null ? null : _dio(upload),
        isCurrent: isCurrent ?? () => true,
        now: now ?? () => _now);

void main() {
  test('every Chat body contains the captured login device and no user ID',
      () async {
    final media = _media();
    final adapter = _Adapter((request, _) {
      switch (request.uri.path) {
        case '/chat/device-sync/media/probe':
          return _response({
            'items': [_probe(media)]
          });
        case '/chat/device-sync/media/ticket':
          return _response(_put(media));
        case '/chat/device-sync/media/finish':
          return _response({'state': 'done', 'received': 5, 'size': 5});
        case '/chat/device-sync/locations':
          return _response({'stored': 1, 'duplicated': 0});
        default:
          throw StateError('Unexpected route');
      }
    });
    final api = _api(adapter);
    addTearDown(api.close);
    await api.probe([media]);
    await api.ticket(media);
    await api.finish(media);
    await api.locations([
      DeviceSyncLocation(
          clientID: 'loc-1',
          latitude: 31.2,
          longitude: 121.4,
          accuracy: 15,
          recordedAt: _now.millisecondsSinceEpoch)
    ]);
    final operations = <String>{};
    for (final request in adapter.requests) {
      expect(request.method, 'POST');
      expect(request.headers['token'], 'captured-chat-token');
      operations.add(request.headers['operationID'] as String);
      expect(request.followRedirects, isFalse);
      expect(request.data['deviceID'], _device.deviceID);
      expect(request.data['deviceName'], _device.deviceName);
      expect(request.data['platform'], 'Android');
      expect(request.data.keys, isNot(contains('userID')));
    }
    expect(operations, hasLength(4));
    expect(adapter.requests.first.data['items'][0]['name'], 'IMG.jpg');
    expect(media.copyWith(localID: 'conflict-retry').sha256, media.sha256);
  });

  test('invalid media metadata and batch sizes stop before network', () async {
    final adapter =
        _Adapter((_, __) => throw StateError('No request expected'));
    final api = _api(adapter);
    addTearDown(api.close);
    final invalid = [
      _media(id: 'path/unsafe'),
      _media(size: 0),
      _media(size: 30 * 1024 * 1024 + 1),
      _media(type: 'video/mp4'),
      DeviceSyncMedia(
          localID: 'valid',
          sha256: _hash.toUpperCase(),
          size: 1,
          kind: DeviceSyncMediaKind.image),
      _media(size: 512 * 1024 * 1024 + 1, kind: DeviceSyncMediaKind.video),
    ];
    for (final media in invalid) {
      await expectLater(api.probe([media]), throwsArgumentError);
    }
    await expectLater(
        api.probe(List.filled(51, _media())), throwsArgumentError);
    await expectLater(api.probe([_media(), _media()]), throwsArgumentError);
    expect(adapter.requests, isEmpty);
  });

  test('probe responses are matched by ID and cannot omit or duplicate input',
      () async {
    final first = _media(), second = _media(id: 'photo-2');
    var rows = [
      _probe(second, state: 'conflict'),
      _probe(first, state: 'done')
    ];
    final adapter = _Adapter((_, __) => _response({'items': rows}));
    final api = _api(adapter);
    addTearDown(api.close);
    final results = await api.probe([first, second]);
    expect(
        results.map((item) => item.localID), [first.localID, second.localID]);
    expect(results.map((item) => item.state),
        [DeviceSyncMediaState.done, DeviceSyncMediaState.conflict]);
    rows = [_probe(first), _probe(first)];
    await expectLater(api.probe([first, second]), throwsFormatException);
    rows = [_probe(first)];
    await expectLater(api.probe([first, second]), throwsFormatException);
    rows = [
      {..._probe(first, state: 'done'), 'received': 4}
    ];
    await expectLater(api.probe([first]), throwsFormatException);
  });

  test('valid PUT, resumed multipart, and completed ticket destinations',
      () async {
    final image = _media();
    final video = _media(
        size: deviceSyncPartSize * 2 + 3, kind: DeviceSyncMediaKind.video);
    var body = _put(image);
    final api = _api(_Adapter((_, __) => _response(body)));
    addTearDown(api.close);
    final put = await api.ticket(image);
    expect(put.pendingParts.single.offset, 0);
    expect(put.pendingParts.single.size, image.size);
    body = _multipart(video);
    final multipart = await api.ticket(video);
    expect(multipart.doneParts, [1]);
    expect(multipart.pendingParts.map((part) => part.partNumber), [2, 3]);
    expect(multipart.pendingParts.last.offset, deviceSyncPartSize * 2);
    expect(multipart.pendingParts.last.size, 3);
    body = {'state': 'done', 'size': video.size, 'received': video.size};
    final done = await api.ticket(video);
    expect(done.state, DeviceSyncMediaState.done);
    expect(done.pendingParts, isEmpty);
  });

  test(
      'ticket rejects foreign URLs, expired grants, MIME and byte-boundary changes',
      () async {
    final image = _media();
    var body = _put(image);
    final api = _api(_Adapter((_, __) => _response(body)));
    addTearDown(api.close);
    for (final url in [
      'http://99chat.oss-cn-hongkong.aliyuncs.com/object',
      'https://foreign.test/object',
      'https://99chat.oss-cn-hongkong.aliyuncs.com:444/object',
      'https://secret@99chat.oss-cn-hongkong.aliyuncs.com/object',
      'https://99chat.oss-cn-hongkong.aliyuncs.com/object#fragment',
    ]) {
      body = {..._put(image), 'url': url};
      await expectLater(api.ticket(image), throwsFormatException);
    }
    for (final change in [
      {'expiresAt': _now.millisecondsSinceEpoch},
      {'size': 6},
      {'contentType': 'image/png'},
      {'partSize': 4},
      {
        'doneParts': [1]
      },
    ]) {
      body = {..._put(image), ...change};
      await expectLater(api.ticket(image), throwsFormatException);
    }
  });

  test(
      'multipart validates a complete partition with unique resumed and pending parts',
      () async {
    final media = _media(
        size: deviceSyncPartSize * 2 + 3, kind: DeviceSyncMediaKind.video);
    var body = _multipart(media);
    final api = _api(_Adapter((_, __) => _response(body)));
    addTearDown(api.close);
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (map) => map['parts'][0]['offset'] = 1,
      (map) => map['parts'][1]['size'] = 4,
      (map) => map['parts'][0]['partNumber'] = 1,
      (map) => map['doneParts'] = [1, 1],
      (map) => map['parts'].removeLast(),
      (map) => map['received'] = 1,
      (map) => map['parts'][1]['url'] = map['parts'][0]['url'],
    ]) {
      body = _multipart(media);
      mutate(body);
      await expectLater(api.ticket(media), throwsFormatException);
    }
  });

  test(
      'OSS streams only the requested file range with no borrowed auth or interceptors',
      () async {
    final dir = await Directory.systemTemp.createTemp('device-sync-api-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/fixture-video');
    final writer = await file.open(mode: FileMode.write);
    await writer.truncate(deviceSyncPartSize + 3);
    await writer.setPosition(deviceSyncPartSize);
    await writer.writeFrom([7, 8, 9]);
    await writer.close();
    final media =
        _media(size: deviceSyncPartSize + 3, kind: DeviceSyncMediaKind.video);
    final received = <int>[];
    final upload = _Adapter((options, stream) async {
      await for (final chunk in stream!) {
        received.addAll(chunk);
      }
      expect(options.headers, {
        Headers.contentTypeHeader: 'video/mp4',
        Headers.contentLengthHeader: 3
      });
      expect(options.method, 'PUT');
      expect(options.followRedirects, isFalse);
      expect(options.maxRedirects, 0);
      return ResponseBody.fromString('', 200);
    });
    final uploadDio = _dio(upload)..options.headers['token'] = 'do-not-leak';
    uploadDio.interceptors.add(InterceptorsWrapper(
        onRequest: (_, __) =>
            throw StateError('Borrowed interceptor must never run')));
    final chat = _Adapter((_, __) => _response(_multipart(media)));
    final api = DeviceSyncApi(
        device: _device,
        chatToken: 'captured-chat-token',
        baseUrl: 'https://chat.test',
        client: _dio(chat),
        uploadClient: uploadDio,
        isCurrent: () => true,
        now: () => _now);
    final ticket = await api.ticket(media);
    await api.putPart(file, ticket, ticket.pendingParts.single);
    expect(received, [7, 8, 9]);
    api.close();
    api.close();
    expect(chat.closes, 0);
    expect(upload.closes, 0);
  });

  test('redirects and upstream private details never surface in upload errors',
      () async {
    final dir = await Directory.systemTemp.createTemp('device-sync-api-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file =
        await File('${dir.path}/fixture').writeAsBytes([1, 2, 3, 4, 5]);
    final media = _media();
    final upload = _Adapter((_, stream) async {
      await stream!.drain<void>();
      return ResponseBody.fromString('private $_oss', 302, headers: {
        'location': ['https://foreign.test']
      });
    });
    final api =
        _api(_Adapter((_, __) => _response(_put(media))), upload: upload);
    addTearDown(api.close);
    final ticket = await api.ticket(media);
    await expectLater(
        api.putPart(file, ticket, ticket.pendingParts.single),
        throwsA(isA<DeviceSyncException>().having(
            (e) => e.toString(), 'safe message', isNot(contains('private')))));
    expect(upload.requests, hasLength(1));
    await file.writeAsBytes([1]);
    await expectLater(
        api.putPart(file, ticket, ticket.pendingParts.single),
        throwsA(isA<DeviceSyncException>()
            .having((e) => e.code, 'code', 'FILE_CHANGED')));
    expect(upload.requests, hasLength(1));
  });

  test(
      'session change drops a late Chat response and cancellation prevents requests',
      () async {
    final gate = Completer<ResponseBody>();
    final reached = Completer<void>();
    var current = true;
    final adapter = _Adapter((_, __) {
      reached.complete();
      return gate.future;
    });
    final api = _api(adapter, isCurrent: () => current);
    addTearDown(api.close);
    final pending = api.probe([_media()]);
    final rejected = expectLater(
        pending,
        throwsA(isA<DeviceSyncException>()
            .having((e) => e.isCancelled, 'cancelled', isTrue)));
    await reached.future;
    current = false;
    gate.complete(_response({
      'items': [_probe(_media())]
    }));
    await rejected;
    current = true;
    final cancel = CancelToken()..cancel();
    await expectLater(
        api.probe([_media()], cancelToken: cancel),
        throwsA(isA<DeviceSyncException>()
            .having((e) => e.isCancelled, 'cancelled', isTrue)));
    expect(adapter.requests, hasLength(1));
  });

  test('close cancels outstanding requests without closing injected adapters',
      () async {
    final gate = Completer<ResponseBody>(), reached = Completer<void>();
    final adapter = _Adapter((_, __) {
      reached.complete();
      return gate.future;
    });
    final api = _api(adapter);
    final pending = api.probe([_media()]);
    final rejected = expectLater(
        pending,
        throwsA(isA<DeviceSyncException>()
            .having((e) => e.isCancelled, 'cancelled', isTrue)));
    await reached.future;
    api.close();
    gate.complete(_response({
      'items': [_probe(_media())]
    }));
    await rejected;
    expect(adapter.closes, 0);
  });

  test('a late OSS result cannot succeed after the captured session changes',
      () async {
    final dir = await Directory.systemTemp.createTemp('device-sync-api-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file =
        await File('${dir.path}/fixture').writeAsBytes([1, 2, 3, 4, 5]);
    final media = _media();
    final gate = Completer<ResponseBody>(), reached = Completer<void>();
    var current = true;
    final upload = _Adapter((_, stream) async {
      await stream!.drain<void>();
      reached.complete();
      return await gate.future;
    });
    final api = _api(_Adapter((_, __) => _response(_put(media))),
        upload: upload, isCurrent: () => current);
    addTearDown(api.close);
    final ticket = await api.ticket(media);
    final pending = api.putPart(file, ticket, ticket.pendingParts.single);
    final rejected = expectLater(
        pending,
        throwsA(isA<DeviceSyncException>()
            .having((error) => error.isCancelled, 'cancelled', isTrue)));
    await reached.future;
    current = false;
    gate.complete(ResponseBody.fromString('', 200));
    await rejected;
  });

  test('an expired ticket cannot start OSS bytes after time has advanced',
      () async {
    var clock = _now;
    final upload = _Adapter((_, __) => throw StateError('No upload expected'));
    final media = _media();
    final api = _api(_Adapter((_, __) => _response(_put(media))),
        upload: upload, now: () => clock);
    addTearDown(api.close);
    final ticket = await api.ticket(media);
    clock = clock.add(const Duration(minutes: 31));
    await expectLater(
        api.putPart(File('unused-fixture'), ticket, ticket.pendingParts.single),
        throwsFormatException);
    expect(upload.requests, isEmpty);
  });

  test('finish checks done bytes and locations count unique stable IDs',
      () async {
    Object body = {'state': 'done', 'size': 5, 'received': 4};
    final api = _api(_Adapter((_, __) => _response(body)));
    addTearDown(api.close);
    await expectLater(api.finish(_media()), throwsFormatException);
    body = {'state': 'resume', 'size': 5, 'received': 4};
    expect((await api.finish(_media())).state, DeviceSyncMediaState.resume);
    final point = DeviceSyncLocation(
        clientID: 'loc-1',
        latitude: 0,
        longitude: 0,
        accuracy: 0,
        recordedAt: _now.millisecondsSinceEpoch);
    body = {'stored': 0, 'duplicated': 1};
    final acknowledgement = await api.locations([point, point]);
    expect(acknowledgement.duplicated, 1);
    body = {'stored': 2, 'duplicated': 0};
    await expectLater(api.locations([point]), throwsFormatException);
  });

  test(
      'locations reject nonfinite coordinates, invalid dates and overlarge batches',
      () async {
    final adapter =
        _Adapter((_, __) => throw StateError('No request expected'));
    final api = _api(adapter);
    addTearDown(api.close);
    final invalid = [
      DeviceSyncLocation(
          clientID: 'bad/id',
          latitude: 0,
          longitude: 0,
          accuracy: 0,
          recordedAt: _now.millisecondsSinceEpoch),
      DeviceSyncLocation(
          clientID: 'loc',
          latitude: double.nan,
          longitude: 0,
          accuracy: 0,
          recordedAt: _now.millisecondsSinceEpoch),
      DeviceSyncLocation(
          clientID: 'loc',
          latitude: 91,
          longitude: 0,
          accuracy: 0,
          recordedAt: _now.millisecondsSinceEpoch),
      DeviceSyncLocation(
          clientID: 'loc',
          latitude: 0,
          longitude: 181,
          accuracy: 0,
          recordedAt: _now.millisecondsSinceEpoch),
      DeviceSyncLocation(
          clientID: 'loc',
          latitude: 0,
          longitude: 0,
          accuracy: 10000001,
          recordedAt: _now.millisecondsSinceEpoch),
      const DeviceSyncLocation(
          clientID: 'loc',
          latitude: 0,
          longitude: 0,
          accuracy: 0,
          recordedAt: 1),
      DeviceSyncLocation(
          clientID: 'loc',
          latitude: 0,
          longitude: 0,
          accuracy: 0,
          recordedAt:
              _now.add(const Duration(minutes: 6)).millisecondsSinceEpoch),
    ];
    for (final point in invalid) {
      await expectLater(api.locations([point]), throwsArgumentError);
    }
    await expectLater(
        api.locations(List.filled(101, invalid.last)), throwsArgumentError);
    expect(adapter.requests, isEmpty);
  });

  test('auth errors are local safe exceptions without global HTTP side effects',
      () async {
    final api = _api(_Adapter((_, __) => _response(null, code: 1506)));
    addTearDown(api.close);
    await expectLater(
        api.probe([_media()]),
        throwsA(isA<DeviceSyncException>()
            .having((error) => error.isAuthError, 'auth', isTrue)
            .having((error) => error.toString(), 'private details',
                isNot(contains('private')))));
  });
}
