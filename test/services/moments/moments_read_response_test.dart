import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_api.dart';

void main() {
  late Dio client;
  late MomentsApi api;
  dynamic body;
  String? contentType;
  int status = 200;
  setUp(() {
    client = Dio();
    status = 200;
    contentType = null;
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(
          requestOptions: request,
          statusCode: status,
          headers: Headers.fromMap({
            if (contentType != null) 'content-type': [contentType!]
          }),
          data: body));
    }));
    api = MomentsApi(
        client: client,
        baseUrl: 'https://business.example',
        tokenProvider: () => 'test-token');
  });
  tearDown(() => client.close(force: true));

  test('successful protojson comment page can omit empty repeated items',
      () async {
    body = {
      'errCode': 0,
      'data': {'viewerContextVersion': 'opaque-context'}
    };
    final page = await api.comments('post');
    expect(page.items, isEmpty);
    expect(page.hasMore, false);
    expect(page.viewerContextVersion, 'opaque-context');
  });
  test('malformed comment pages and broken continuation remain errors',
      () async {
    for (final data in [
      {},
      {'viewerContextVersion': ''},
      {'viewerContextVersion': 'context', 'items': 123},
      {'viewerContextVersion': 'context', 'hasMore': true}
    ]) {
      body = {'errCode': 0, 'data': data};
      await expectLater(api.comments('post'), throwsFormatException);
    }
  });
  test('empty user timeline and notifications accept live protojson payloads',
      () async {
    body = {
      'errCode': 0,
      'data': {'viewerContextVersion': 'context'}
    };
    expect((await api.userMoments('me')).items, isEmpty);
    expect((await api.feed()).items, isEmpty);
    body = {
      'errCode': 0,
      'data': {'viewerContextVersion': 'context', 'seenWatermark': 'watermark'}
    };
    final notifications = await api.notifications();
    expect(notifications.items, isEmpty);
    expect(notifications.unreadCount, 0);
    expect(notifications.seenWatermark, 'watermark');
    expect(notifications.hasMore, isFalse);
  });
  test('user and notification pages still reject malformed payloads', () async {
    for (final data in [
      {},
      {'viewerContextVersion': ''},
      {'viewerContextVersion': 'context', 'items': 123},
      {'viewerContextVersion': 'context', 'hasMore': true}
    ]) {
      body = {'errCode': 0, 'data': data};
      await expectLater(api.userMoments('me'), throwsFormatException);
      await expectLater(api.notifications(), throwsFormatException);
    }
  });
  test('media HTTP 200 business error is never returned as image bytes',
      () async {
    body = utf8.encode(jsonEncode({
      'errCode': 20012,
      'errMsg': 'Forbidden',
      'errDlt': 'RELATION_UNAVAILABLE'
    }));
    for (final type in [
      'application/json; charset=utf-8',
      'application/octet-stream'
    ]) {
      contentType = type;
      await expectLater(
          api.downloadMedia(const MomentMedia(mediaId: 'photo')),
          throwsA(isA<MomentsException>()
              .having((e) => e.code, 'code', 'RELATION_UNAVAILABLE')
              .having(
                  (e) => e.relationUnavailable, 'relation unavailable', true)));
    }
  });
  test(
      'media permission failures preserve their business reason at HTTP 200/403',
      () async {
    body = utf8.encode(jsonEncode({
      'errCode': 20012,
      'errMsg': 'Forbidden',
      'errDlt': 'MOMENT_UNAVAILABLE'
    }));
    contentType = 'application/json';
    for (final code in [200, 403]) {
      status = code;
      await expectLater(
          api.downloadMedia(const MomentMedia(mediaId: 'photo')),
          throwsA(isA<MomentsException>()
              .having((e) => e.permissionDenied, 'permission denied', true)));
    }
  });
  test('invalid JSON media and JSON success payload are rejected', () async {
    contentType = 'application/json';
    for (final value in ['not json', '[]', '{"errCode":0,"data":{}}']) {
      body = utf8.encode(value);
      await expectLater(
          api.downloadMedia(const MomentMedia(mediaId: 'photo')),
          throwsA(isA<MomentsException>()
              .having((e) => e.code, 'code', 'INVALID_MEDIA_RESPONSE')));
    }
  });
  test('binary image bytes pass through unchanged', () async {
    contentType = 'image/png';
    body = [137, 80, 78, 71, 13, 10, 26, 10];
    expect(await api.downloadMedia(const MomentMedia(mediaId: 'photo')), body);
  });
}
