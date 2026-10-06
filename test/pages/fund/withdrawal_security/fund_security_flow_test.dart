import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/withdrawal_security/withdrawal_security.dart';
import 'package:openim/pages/fund/withdrawal_security/presentation/fund_security_code_sheet.dart';
import 'package:openim/pages/fund/widgets/fund_page_colors.dart';
import 'package:openim/services/fund_api.dart';

const _exportPreviews = bool.fromEnvironment('EXPORT_FUND_SECURITY_PREVIEWS');

FundSecurityRequest _request() => FundSecurityRequest.withdrawal({
      'clientOrderID': 'original-business-id',
      'mode': 'chain',
      'network': 'TRON',
      'currency': 'USDT',
      'amount': '10',
      'toAddress': 'user-entered-address',
    });

class _Api extends FundApi {
  final calls = <({String path, Map<String, dynamic>? body})>[];
  bool smsRequired = true;
  int blockedUntil = 0;
  String phone = '+86 138****8000';
  Object? checkError, codeError;
  Future<Map<String, dynamic>> Function()? checking, sending;
  int sends = 0;
  DateTime now = DateTime.now();

  Map<String, dynamic> checkResponse() => {
        'smsRequired': smsRequired,
        'reasons': smsRequired ? ['new_device'] : [],
        'blockedUntil': blockedUntil,
        'phoneMasked': phone,
        'currency': 'USDT',
        'smsThreshold': '5',
        'cooldownHours': 24,
      };
  Map<String, dynamic> codeResponse() => {
        'challengeID': 'challenge-$sends',
        'expiresAt': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
        'retryAfterSeconds': 60,
        'phoneMasked': phone,
      };

  @override
  Future<Map<String, dynamic>> requestData(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool mutation = false,
  }) async {
    calls.add((path: path, body: data));
    if (path.endsWith('/check')) {
      if (checkError != null) throw checkError!;
      return checking == null ? checkResponse() : await checking!();
    }
    sends++;
    if (codeError != null) throw codeError!;
    return sending == null ? codeResponse() : await sending!();
  }
}

class _Result {
  bool current = true, finished = false;
  Object? value;
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _open(
  WidgetTester tester,
  _Api api,
  _Result result, {
  bool authorize = true,
  Brightness brightness = Brightness.light,
  Size size = const Size(375, 812),
  double scale = 1,
  EdgeInsets keyboard = EdgeInsets.zero,
  GlobalKey? boundaryKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
        brightness: brightness,
        fontFamily: _exportPreviews ? 'FundSecurityPreviewCjk' : null),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), viewInsets: keyboard),
        child: child!),
    home: Builder(
        builder: (context) => Scaffold(
              body: ElevatedButton(
                  key: const ValueKey('start'),
                  onPressed: () async {
                    result.value = authorize
                        ? await authorizeFundSecurity(context,
                            request: _request(),
                            api: api,
                            isCurrent: () => result.current)
                        : await showModalBottomSheet<Object>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => FundSecurityCodeSheet(
                                request: _request(),
                                security: FundWithdrawalSecurityApi(api),
                                phoneMasked: api.phone,
                                isCurrent: () => result.current,
                                now: () => api.now));
                    result.finished = true;
                  },
                  child: const Text('开始安全验证')),
            )),
  );
  await tester.pumpWidget(boundaryKey == null
      ? app
      : RepaintBoundary(key: boundaryKey, child: app));
  await tester.tap(_key('start'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!_exportPreviews) return;
    for (final entry in {
      'FundSecurityPreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(entry.value);
      if (!file.existsSync()) continue;
      await (FontLoader(entry.key)
            ..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes()))))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('optional SMS preview ${brightness.name}', (tester) async {
      final boundary = GlobalKey();
      final api = _Api();
      final result = _Result();
      await _open(tester, api, result,
          brightness: brightness, boundaryKey: boundary);
      await tester.enterText(_key('fund-security-code'), '012345');
      // Let the real enabled-button text animation finish before capture.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          tester.widget<FilledButton>(_key('fund-security-confirm')).onPressed,
          isNotNull);
      expect(
          DefaultTextStyle.of(tester.element(find.text('继续支付'))).style.color,
          tester
              .widget<FilledButton>(_key('fund-security-confirm'))
              .style!
              .foregroundColor!
              .resolve({}));
      // Export the real production sheet, using local masked test data only.
      // No SMS endpoint or payment endpoint is contacted by this fixture.
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('docs/previews')
            ..createSync(recursive: true);
          await File(
                  '${directory.path}/fund-security-sms-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      expect(tester.takeException(), isNull);
      expect(api.calls.map((call) => call.path),
          everyElement(startsWith('/chat/fund/withdrawal-security/')));
      await tester.tap(_key('fund-security-cancel'));
      await tester.pumpAndSettle();
    }, skip: !_exportPreviews);
  }

  testWidgets('no SMS required returns empty proof and never sends SMS',
      (tester) async {
    final api = _Api()..smsRequired = false;
    final result = _Result();
    await _open(tester, api, result);
    expect(result.finished, isTrue);
    expect((result.value as FundSecurityProof).toJson(), isEmpty);
    expect(api.calls.single.path, '/chat/fund/withdrawal-security/check');
    expect(_key('fund-security-sheet'), findsNothing);
  });

  testWidgets('waiting period precedes SMS and displays UTC+8 allowed time',
      (tester) async {
    final api = _Api()
      ..blockedUntil =
          DateTime.utc(2026, 10, 7, 0, 1, 2).millisecondsSinceEpoch;
    final result = _Result();
    await _open(tester, api, result);
    expect(find.textContaining('2026-10-07 08:01:02（UTC+8）'), findsOneWidget);
    expect(api.sends, 0);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
    expect(result.finished, isTrue);
  });

  testWidgets('missing sender phone never skips required SMS', (tester) async {
    final api = _Api()..phone = '';
    final result = _Result();
    await _open(tester, api, result);
    expect(find.textContaining('请先绑定手机号'), findsOneWidget);
    expect(api.sends, 0);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
  });

  testWidgets('business check errors use Chinese rather than raw server errors',
      (tester) async {
    final api = _Api()
      ..checkError = const FundApiException(20079, 'device not found');
    final result = _Result();
    await _open(tester, api, result);
    expect(find.textContaining('重新登录'), findsOneWidget);
    expect(find.textContaining('device not found'), findsNothing);
    expect(api.sends, 0);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
  });

  testWidgets(
      'SMS input returns real proof, never a payment or another purpose code',
      (tester) async {
    final api = _Api();
    final result = _Result();
    await _open(tester, api, result);
    expect(find.textContaining('+86 138****8000'), findsOneWidget);
    expect(api.sends, 1);
    expect(
        api.calls.map((call) => call.body), everyElement(_request().toJson()));
    expect(
        (tester.widget<FilledButton>(_key('fund-security-confirm'))).onPressed,
        isNull);
    await tester.enterText(_key('fund-security-code'), '012345');
    await tester.pump();
    await tester.tap(_key('fund-security-confirm'));
    await tester.pumpAndSettle();
    final proof = result.value as FundSecurityProof;
    expect(proof.challengeID, 'challenge-1');
    expect(proof.code, '012345');
    expect(proof.expiresAt, isNotNull);
    expect(api.calls, hasLength(2));
  });

  testWidgets(
      'cancel during send ignores its late response and produces no proof',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = _Api()..sending = () => pending.future;
    final result = _Result();
    await _open(tester, api, result);
    await tester.tap(_key('fund-security-cancel'));
    await tester.pumpAndSettle();
    expect(result.finished, isTrue);
    expect(result.value, isNull);
    pending.complete(api.codeResponse());
    await tester.pumpAndSettle();
    expect(_key('fund-security-sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'sender session change after precheck cannot send SMS or yield proof',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = _Api()..checking = () => pending.future;
    final result = _Result();
    await _open(tester, api, result);
    result.current = false;
    pending.complete(api.checkResponse());
    await tester.pumpAndSettle();
    expect(result.finished, isTrue);
    expect(result.value, isNull);
    expect(api.sends, 0);
  });

  testWidgets('sender session change closes SMS and wipes entered code',
      (tester) async {
    final api = _Api();
    final result = _Result();
    await _open(tester, api, result, authorize: false);
    await tester.enterText(_key('fund-security-code'), '012345');
    result.current = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(result.finished, isTrue);
    expect(result.value, isNull);
    expect(_key('fund-security-sheet'), findsNothing);
  });

  testWidgets('stale covered SMS sheet never pops an unrelated page',
      (tester) async {
    final api = _Api();
    final result = _Result();
    await _open(tester, api, result, authorize: false);
    final navigator = Navigator.of(tester.element(_key('fund-security-sheet')));
    unawaited(navigator.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他页面')))));
    await tester.pumpAndSettle();
    result.current = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('其他页面'), findsOneWidget);
    expect(result.finished, isTrue);
    expect(result.value, isNull);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(_key('fund-security-sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete SMS success leaves no usable challenge',
      (tester) async {
    final api = _Api()..sending = () async => {'challengeID': 'incomplete'};
    final result = _Result();
    await _open(tester, api, result);
    expect(find.textContaining('安全验证信息获取失败'), findsOneWidget);
    expect(
        tester.widget<TextField>(_key('fund-security-code')).enabled, isFalse);
    expect(tester.widget<FilledButton>(_key('fund-security-confirm')).onPressed,
        isNull);
    await tester.tap(_key('fund-security-cancel'));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
  });

  testWidgets(
      'binding/device failures while sending stop and show recovery help',
      (tester) async {
    final api = _Api()
      ..codeError = const FundApiException(20038, 'missing phone');
    final result = _Result();
    await _open(tester, api, result);
    expect(_key('fund-security-sheet'), findsNothing);
    expect(find.textContaining('请先绑定手机号'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(result.finished, isTrue);
    expect(result.value, isNull);
  });

  testWidgets('resend is delayed and only newest challenge/code can continue',
      (tester) async {
    final api = _Api();
    final result = _Result();
    await _open(tester, api, result, authorize: false);
    expect(find.text('60s 后重发'), findsOneWidget);
    expect(tester.widget<TextButton>(_key('fund-security-resend')).onPressed,
        isNull);
    await tester.enterText(_key('fund-security-code'), '012345');
    api.now = api.now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(_key('fund-security-resend'));
    await tester.pump();
    expect(api.sends, 2);
    expect(
        tester.widget<TextField>(_key('fund-security-code')).controller!.text,
        isEmpty);
    await tester.enterText(_key('fund-security-code'), '678901');
    await tester.pump();
    await tester.tap(_key('fund-security-confirm'));
    await tester.pumpAndSettle();
    expect((result.value as FundSecurityProof).challengeID, 'challenge-2');
    expect((result.value as FundSecurityProof).code, '678901');
  });

  testWidgets(
      'expired challenge disables continue rather than treating code as authorized',
      (tester) async {
    final api = _Api();
    final result = _Result();
    await _open(tester, api, result, authorize: false);
    await tester.enterText(_key('fund-security-code'), '012345');
    api.now = api.now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('验证码已过期，请重新获取'), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('fund-security-confirm')).onPressed,
        isNull);
    expect(
        tester.widget<TextField>(_key('fund-security-code')).enabled, isFalse);
    await tester.tap(_key('fund-security-cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('SMS outage preserves retry and cannot bypass verification',
      (tester) async {
    final api = _Api()
      ..codeError = const FundApiException(500, 'SMS upstream offline');
    final result = _Result();
    await _open(tester, api, result);
    expect(find.textContaining('错误码：500'), findsOneWidget);
    expect(find.textContaining('upstream'), findsNothing);
    expect(tester.widget<FilledButton>(_key('fund-security-confirm')).onPressed,
        isNull);
    api.codeError = null;
    await tester.tap(_key('fund-security-resend'));
    await tester.pump();
    expect(api.sends, 2);
    expect(
        tester.widget<TextField>(_key('fund-security-code')).enabled, isTrue);
    await tester.tap(_key('fund-security-cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'send frequency failure enforces retry delay without retaining previous challenge',
      (tester) async {
    final api = _Api()
      ..codeError = const FundApiException(20080, 'too frequent');
    final result = _Result();
    await _open(tester, api, result, authorize: false);
    expect(find.text('60s 后重发'), findsOneWidget);
    expect(find.textContaining('短信发送过于频繁'), findsOneWidget);
    expect(tester.widget<TextButton>(_key('fund-security-resend')).onPressed,
        isNull);
    expect(tester.widget<FilledButton>(_key('fund-security-confirm')).onPressed,
        isNull);
    await tester.tap(_key('fund-security-cancel'));
    await tester.pumpAndSettle();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} keyboard and large text sheet is readable and scrollable',
        (tester) async {
      final api = _Api();
      final result = _Result();
      await _open(tester, api, result,
          authorize: false,
          brightness: brightness,
          size: const Size(320, 640),
          scale: 2,
          keyboard: const EdgeInsets.only(bottom: 280));
      expect(tester.takeException(), isNull);
      final context = tester.element(_key('fund-security-code'));
      final colors = FundPageColors.of(context);
      final field = tester.widget<TextField>(_key('fund-security-code'));
      expect(field.style!.color, colors.text);
      expect(field.decoration!.fillColor, colors.inputFill);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      await tester.ensureVisible(_key('fund-security-cancel'));
      await tester.tap(_key('fund-security-cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
