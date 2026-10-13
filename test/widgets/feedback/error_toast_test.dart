import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim_common/openim_common.dart';

const _dnsError = 'DioException [connection error]: The connection errored: '
    "Failed host lookup: '99chatapi.99chat.vip' This indicates a...";
const _resetError = 'DioException [connection error]: The connection errored: '
    'Connection reset by peer This indicates a...';
const _redisError = 'PlatformException(500, 500 Error: MISCONF Redis is '
    "configured to save RDB snapshots, but it's currently unable..., null, null)";
const _network = '网络连接失败，请检查网络后重试';
const _timeout = '服务器响应较慢，请稍后重试';
const _service = '服务暂时不可用，请稍后重试';

void main() {
  setUp(() {
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(Get.reset);

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
  ]) {
    test('Dio $type uses a short retry prompt', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/chat'),
        type: type,
        message: 'private server address /tmp/request.go',
      );
      expect(HttpUtil.errorMessage(error), _timeout);
    });
  }

  test('DNS failures and connection resets ask to check the network', () {
    for (final detail in ['Failed host lookup', 'Connection reset by peer']) {
      expect(
        HttpUtil.errorMessage(DioException(
          requestOptions: RequestOptions(path: '/chat'),
          type: DioExceptionType.connectionError,
          message: detail,
        )),
        _network,
      );
    }
    expect(
        HttpUtil.errorMessage(const SocketException('private host')), _network);
  });

  test('native SDK and Dart timeouts receive the same prompt', () {
    expect(
        HttpUtil.errorMessage(TimeoutException('private request')), _timeout);
    expect(HttpUtil.errorMessage(PlatformException(code: '10001')), _timeout);
    expect(
      HttpUtil.errorMessage(PlatformException(
          code: '10000', message: 'context deadline exceeded')),
      _timeout,
    );
    expect(
      HttpUtil.errorMessage(PlatformException(
          code: '10000', message: 'Connection reset by peer')),
      _network,
    );
  });

  test('server and Redis errors hide internal details', () {
    expect(
      HttpUtil.errorMessage(PlatformException(
        code: '500',
        message: 'MISCONF Redis RDB snapshots /var/private.rdb',
        details: {'stack': 'private token'},
      )),
      _service,
    );
    expect(HttpUtil.errorMessage((500, 'MISCONF Redis')), _service);
    expect(HttpUtil.errorMessage(PlatformException(code: '503')), _service);
    expect(
      HttpUtil.errorMessage(DioException(
        requestOptions: RequestOptions(path: '/chat'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/chat'),
          statusCode: 500,
          data: '<html>private server stack</html>',
        ),
      )),
      _service,
    );
  });

  test('business and session reasons retain their specific localized prompts',
      () {
    expect(
      HttpUtil.errorMessage(
          PlatformException(code: '1203', message: 'raw stack')),
      '用户不在群组中',
    );
    expect(
      HttpUtil.errorMessage(
          PlatformException(code: '1501', message: 'raw token')),
      ApiErrorMessages.sessionExpired,
    );
    expect(
      HttpUtil.errorMessage(DioException(
        requestOptions: RequestOptions(path: '/account/login'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/account/login'),
          statusCode: 403,
          data: {'errCode': 20001, 'errMsg': 'private password error'},
        ),
      )),
      '密码错误',
    );
  });

  test(
      'unknown exceptions respect contextual fallback without exposing details',
      () {
    expect(
      HttpUtil.errorMessage(
          PlatformException(
              code: 'channel-error', message: 'private native channel'),
          fallback: '收藏失败，请稍后重试'),
      '收藏失败，请稍后重试',
    );
    expect(HttpUtil.errorMessage(StateError('private state')),
        ApiErrorMessages.requestFailed);
  });

  test('Dio unknown errors still classify wrapped native transport failures',
      () {
    expect(
      HttpUtil.errorMessage(DioException(
        requestOptions: RequestOptions(path: '/chat'),
        error: TimeoutException('private server'),
      )),
      _timeout,
    );
    expect(
      HttpUtil.errorMessage(DioException(
        requestOptions: RequestOptions(path: '/chat'),
        error: const SocketException('private host'),
      )),
      _network,
    );
    expect(HttpUtil.errorMessage(const FormatException('private JSON')),
        ApiErrorMessages.invalidResponse);
  });

  for (final sample in [
    (raw: _dnsError, copy: _network),
    (raw: _resetError, copy: _network),
    (raw: _redisError, copy: _service),
    (raw: 'DioException [receive timeout]: private request', copy: _timeout),
    (raw: '收藏失败：DioException [connection error]: private host', copy: _network),
    (
      raw: 'PlatformException(channel-error, private channel, null, null)',
      copy: '请求失败，请稍后重试'
    ),
    (raw: '(500, MISCONF Redis private.rdb)', copy: _service),
    (
      raw: 'PlatformException(10001, private request, null, null)',
      copy: _timeout
    ),
    (raw: 'SocketException: Failed host lookup: private host', copy: _network),
    (raw: 'TimeoutException after 0:00:30: private request', copy: _timeout),
    (raw: '网络恢复后可以重试（network timeout）', copy: '网络恢复后可以重试（network timeout）'),
    (raw: '所选消息包含无法转发的消息，请取消勾选后重试', copy: '所选消息包含无法转发的消息，请取消勾选后重试'),
    (raw: '已保存', copy: '已保存'),
  ]) {
    testWidgets('toast renders friendly copy for ${sample.raw}',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        builder: EasyLoading.init(),
        home: const Scaffold(),
      ));
      final shown = IMViews.showToast(sample.raw);
      await tester.pumpAndSettle();
      await shown;
      expect(find.text(sample.copy), findsOneWidget);
      if (sample.copy != sample.raw) {
        expect(find.text(sample.raw), findsNothing);
      }
      await EasyLoading.dismiss(animation: false);
      await tester.pump();
    });
  }

  testWidgets('structured error entry shows friendly native service feedback',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: EasyLoading.init(),
      home: const Scaffold(),
    ));
    final shown = IMViews.showErrorToast(
        PlatformException(code: '500', message: 'MISCONF Redis private.rdb'));
    await tester.pumpAndSettle();
    await shown;
    expect(find.text(_service), findsOneWidget);
    expect(find.textContaining('Redis'), findsNothing);
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
  });

  test('structured error entry preserves silent risk feedback policy',
      () async {
    await IMViews.showErrorToast((20201, 'private risk detail'),
        path: '/chat/friend-apply');
    expect(EasyLoading.isShow, isFalse);
    expect(
        HttpUtil.isSilentError((20201, 'private risk detail'),
            path: '/chat/friend-apply'),
        isTrue);
  });

  test('messages switch language when the failure is displayed', () {
    final error =
        PlatformException(code: '500', message: 'private Redis detail');
    expect(HttpUtil.errorMessage(error), _service);
    Get.locale = const Locale('en', 'US');
    expect(HttpUtil.errorMessage(error),
        'The service is unavailable. Please try again later.');
    expect(HttpUtil.errorMessage(TimeoutException('private request')),
        'The server is taking longer to respond. Please try again later.');
  });
}
