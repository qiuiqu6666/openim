import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/register/profile/registration_avatar_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _HTTP implements HttpClientAdapter {
  int requests = 0;
  RequestOptions? request;
  Completer<ResponseBody>? response;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    requests++;
    request = options;
    response = Completer<ResponseBody>();
    return response!.future;
  }

  void respond({int error = 0}) => response!.complete(ResponseBody.fromString(
        jsonEncode({
          'errCode': error,
          'errMsg': 'backend profile failure',
          'data': {}
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      ));
}

const _url = 'https://cdn.example.com/avatar.png';

Future<void> _flushUntil(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(ready(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  const service = RegistrationAvatarService();
  late _HTTP adapter;
  late Completer<Object?>? uploaded;
  late Map<Object?, Object?>? nativeArguments;
  late int uploads;
  late RegistrationAvatar avatar;
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'chat-token',
      'imToken': 'im-token',
    }));
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = 'im-token';
    avatar = RegistrationAvatar(
        path: '/test/photo.png',
        name: 'photo.png',
        bytes: Uint8List.fromList([1, 2, 3]));
    uploaded = null;
    nativeArguments = null;
    uploads = 0;
    http.dio = Dio();
    HttpUtil.init();
    adapter = _HTTP();
    http.dio.httpClientAdapter = adapter;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      expect(call.method, 'uploadFile');
      uploads++;
      nativeArguments = call.arguments as Map;
      uploaded = Completer<Object?>();
      return uploaded!.future;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    http.dio.close(force: true);
    Get.reset();
  });

  testWidgets(
      'upload finishes only after the authenticated avatar profile save',
      (tester) async {
    await tester.runAsync(() async {
      var completed = false;
      final pending = service
          .upload(avatar, userID: 'self', isCurrent: () => true)
          .then((value) {
        completed = true;
        return value;
      });
      await _flushUntil(() => uploads == 1);
      expect(nativeArguments!['filePath'], avatar.path);
      expect(nativeArguments!['name'], avatar.name);
      expect(nativeArguments!['id'], isNotEmpty);
      expect(adapter.requests, 0);
      uploaded!.complete(jsonEncode({'url': _url}));
      await _flushUntil(() => adapter.requests == 1);
      expect(completed, isFalse);
      expect(adapter.request!.path, Urls.updateUserInfo);
      expect(adapter.request!.headers['token'], 'chat-token');
      expect(adapter.request!.data['userID'], 'self');
      expect(adapter.request!.data['faceURL'], _url);
      adapter.respond();
      expect(await pending, _url);
      expect(completed, isTrue);
    });
  });

  testWidgets('stale upload never starts SDK or profile requests',
      (tester) async {
    await tester.runAsync(() async {
      expect(
          await service.upload(avatar, userID: 'self', isCurrent: () => false),
          isNull);
    });
    expect(uploads, 0);
    expect(adapter.requests, 0);
  });

  testWidgets('stale SDK upload result never saves the profile',
      (tester) async {
    await tester.runAsync(() async {
      var current = true;
      final pending =
          service.upload(avatar, userID: 'self', isCurrent: () => current);
      await _flushUntil(() => uploads == 1);
      current = false;
      uploaded!.complete({'url': _url});
      expect(await pending, isNull);
      expect(adapter.requests, 0);
    });
  });

  testWidgets(
      'stale profile save does not return an avatar for the new session',
      (tester) async {
    await tester.runAsync(() async {
      var current = true;
      final pending =
          service.upload(avatar, userID: 'self', isCurrent: () => current);
      await _flushUntil(() => uploads == 1);
      uploaded!.complete({'url': _url});
      await _flushUntil(() => adapter.requests == 1);
      current = false;
      adapter.respond();
      expect(await pending, isNull);
    });
  });

  testWidgets('profile business failure propagates without a second toast',
      (tester) async {
    var shown = 0;
    void onStatus(EasyLoadingStatus status) {
      if (status == EasyLoadingStatus.show) shown++;
    }

    EasyLoading.addStatusCallback(onStatus);
    addTearDown(() => EasyLoading.removeCallback(onStatus));
    await tester.runAsync(() async {
      final pending =
          service.upload(avatar, userID: 'self', isCurrent: () => true);
      await _flushUntil(() => uploads == 1);
      uploaded!.complete({'url': _url});
      await _flushUntil(() => adapter.requests == 1);
      final failed = expectLater(
          pending,
          throwsA(predicate<Object>(
              (error) => error is (int, String?) && error.$1 == 1001)));
      adapter.respond(error: 1001);
      await failed;
    });
    expect(shown, 0);
    expect(EasyLoading.isShow, isFalse);
    expect(adapter.requests, 1);
  });

  testWidgets('invalid SDK avatar URL cannot be saved into a profile',
      (tester) async {
    await tester.runAsync(() async {
      final pending =
          service.upload(avatar, userID: 'self', isCurrent: () => true);
      await _flushUntil(() => uploads == 1);
      final failed = expectLater(pending, throwsFormatException);
      uploaded!.complete({'url': 'invalid-avatar-url'});
      await failed;
      expect(adapter.requests, 0);
    });
  });

  testWidgets('SDK upload failure cannot proceed to profile save',
      (tester) async {
    await tester.runAsync(() async {
      final pending =
          service.upload(avatar, userID: 'self', isCurrent: () => true);
      await _flushUntil(() => uploads == 1);
      final failed = expectLater(pending, throwsA(isA<PlatformException>()));
      uploaded!.completeError(PlatformException(code: 'upload-failed'));
      await failed;
      expect(adapter.requests, 0);
    });
  });
}
