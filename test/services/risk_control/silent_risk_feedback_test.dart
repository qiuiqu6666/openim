import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;

class _RiskAdapter implements HttpClientAdapter {
  int status = 429;
  int code = 20201;
  String detail = '操作过于频繁，请稍后再试';
  int requests = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    return ResponseBody.fromString(
      jsonEncode({
        'errCode': code,
        'errMsg': 'server-message',
        'errDlt': detail,
        'data': {'retryAfter': 60},
      }),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'retry-after': ['60'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio previousClient;
  late _RiskAdapter adapter;

  setUp(() {
    previousClient = http.dio;
    adapter = _RiskAdapter();
    http.dio = Dio()..httpClientAdapter = adapter;
  });

  tearDown(() async {
    http.dio.close(force: true);
    http.dio = previousClient;
    await EasyLoading.dismiss(animation: false);
    Get.reset();
  });

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(GetMaterialApp(
        locale: const Locale('zh', 'CN'),
        translations: TranslationService(),
        builder: EasyLoading.init(),
        home: const Scaffold(),
      ));

  Future<void> request(WidgetTester tester, String path) async {
    await tester.runAsync(() => expectLater(
        HttpUtil.post('https://example.test$path'),
        throwsA(isA<(int, String?)>()
            .having((error) => error.$1, 'error code', adapter.code))));
    await tester.pumpAndSettle();
  }

  for (final path in [
    '/chat/friend-apply',
    '/chat/friend-grants',
    '/chat/friend-invites/?entry=qr',
  ]) {
    for (final status in [200, 429]) {
      testWidgets('$path HTTP $status rejects silently without retrying',
          (tester) async {
        adapter.status = status;
        await mount(tester);
        await request(tester, path);
        expect(EasyLoading.isShow, isFalse);
        expect(adapter.requests, 1);
      });
    }
  }

  for (final path in [
    '/account/login',
    '/account/register',
    '/account/code/send',
    '/chat/fund/pay-password',
    '/chat/fund/withdrawals',
    '/chat/fund/transfers',
    '/unknown',
  ]) {
    testWidgets('$path retains necessary failure feedback', (tester) async {
      await mount(tester);
      await request(tester, path);
      expect(EasyLoading.isShow, isTrue);
      expect(find.text(HttpUtil.errorMessage((20201, adapter.detail))),
          findsOneWidget);
    });
  }

  for (final code in [20081, 20202, 20203, 1502]) {
    testWidgets('friend endpoint does not hide verification/service code $code',
        (tester) async {
      adapter.code = code;
      adapter.status = code == 20203 ? 503 : 200;
      await mount(tester);
      await request(tester, '/chat/friend-apply');
      expect(EasyLoading.isShow, isTrue);
    });
  }

  test('raw transport errors use their endpoint, not just the risk code', () {
    for (final path in ['/chat/friend-grants', '/chat/fund/withdrawals']) {
      final request = RequestOptions(path: path);
      final error = DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 429,
          data: jsonEncode({'errCode': 20201, 'errMsg': 'limited'}),
        ),
      );
      expect(HttpUtil.isSilentError(error), path == '/chat/friend-grants');
    }
    expect(isSilentFriendRisk(const FormatException('bad response')), isFalse);
    expect(isSilentFriendRisk((20020, 'invite invalid')), isFalse);
    expect(isSilentFriendRisk((20020, 'group protected')), isFalse);
    expect(isSilentFriendRisk((20201, null)), isTrue);
  });
}
