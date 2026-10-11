import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:openim/pages/mine/settings/verification_code_result.dart';
import 'package:openim/pages/mine/settings/widgets/aliyun_captcha_dialog.dart';

class _Platform extends WebViewPlatform {
  final controllers = <_Controller>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    final controller = _Controller(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _Navigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  late JavaScriptChannelParams channel;
  final scripts = <String>[];
  Completer<void>? scriptResponse;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
    await scriptResponse?.future;
  }

  void emit(Map<String, dynamic> message) => channel
      .onMessageReceived(JavaScriptMessage(message: jsonEncode(message)));
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      testWidgets('load timeout can return without sending ($platform, $dark)',
          (tester) async {
        var sends = 0;
        var closed = false;
        final webview = await _openRecoveryDialog(tester, (_) async {
          sends++;
          return const VerificationCodeResult(
              captchaVerified: true, sent: true);
        }, platform: platform, dark: dark, onClose: (_) => closed = true);
        await tester.pump(const Duration(seconds: 26));
        expect(find.text('验证加载失败，请检查网络后重试'), findsOneWidget);
        // A stale ready callback cannot hide recovery after the timeout.
        webview.controllers.single.emit({'type': 'ready'});
        await tester.pump();
        expect(find.text('重新加载'), findsOneWidget);
        await tester.tap(find.text('返回'));
        await tester.pumpAndSettle();
        expect(sends, 0);
        expect(closed, isTrue);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('reload ignores callbacks from the old WebView', (tester) async {
    final webview = await _openRecoveryDialog(
        tester,
        (_) async =>
            const VerificationCodeResult(captchaVerified: true, sent: true));
    final first = webview.controllers.single;
    first.emit({'type': 'error'});
    await tester.pump();
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    first.emit({'type': 'ready'});
    await tester.pump();
    expect(find.text('返回'), findsOneWidget);
    webview.controllers.last.emit({'type': 'ready'});
    await tester.pump();
    expect(find.text('返回'), findsNothing);
    webview.controllers.last.emit({'type': 'close', 'reason': 'userDismiss'});
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('unanswered backend request times out and ignores late success',
      (tester) async {
    final response = Completer<VerificationCodeResult>();
    VerificationCodeResult? result;
    var closed = false;
    final webview = await _openRecoveryDialog(tester, (_) => response.future,
        onClose: (value) {
      result = value;
      closed = true;
    });
    final controller = webview.controllers.single;
    controller.emit({'type': 'ready'});
    controller.emit({'type': 'verify', 'id': 1, 'captchaVerifyParam': 'proof'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 41));
    await tester.pump();
    expect(webview.controllers, hasLength(2));
    expect(find.text('返回'), findsOneWidget);
    response.complete(
        const VerificationCodeResult(captchaVerified: true, sent: true));
    await tester.pump();
    expect(result, isNull);
    // The feedback overlay is independent of the request/route under test.
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(closed, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('accepted SMS closes even if the JavaScript reply never finishes',
      (tester) async {
    const accepted = VerificationCodeResult(captchaVerified: true, sent: true);
    VerificationCodeResult? result;
    final webview = await _openRecoveryDialog(tester, (_) async => accepted,
        onClose: (value) => result = value);
    final controller = webview.controllers.single;
    final bridge = Completer<void>();
    controller.scriptResponse = bridge;
    controller.emit({'type': 'ready'});
    controller.emit({'type': 'verify', 'id': 1, 'captchaVerifyParam': 'proof'});
    await tester.pump();
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(result, accepted);
    bridge.complete();
    await tester.pump();
    expect(find.text('open'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final result in [
    const VerificationCodeResult(captchaVerified: false, sent: false),
    const VerificationCodeResult(captchaVerified: true, sent: false),
    const VerificationCodeResult(captchaVerified: true, sent: true),
  ]) {
    testWidgets('mobile bridge honors ${result.sdkResult}', (tester) async {
      final platform = _Platform();
      final previous = WebViewPlatform.instance;
      WebViewPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        WebViewPlatform.instance = previous ?? _Platform();
        debugDefaultTargetPlatformOverride = null;
      });
      final response = Completer<VerificationCodeResult>();
      var sends = 0;
      VerificationCodeResult? completed;
      await tester.pumpWidget(MaterialApp(
          builder: EasyLoading.init(),
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        completed = await showAliyunCaptcha(context, (param) {
                          expect(param, '  {"proof":"raw"}  ');
                          sends++;
                          return response.future;
                        });
                      },
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final controller = platform.controllers.single;
      controller.emit({'type': 'ready'});
      await tester.pump();
      controller.emit({
        'type': 'verify',
        'id': 1,
        'captchaVerifyParam': '  {"proof":"raw"}  '
      });
      await tester.pump();
      expect(sends, 1);
      controller
          .emit({'type': 'verify', 'id': 2, 'captchaVerifyParam': 'duplicate'});
      await tester.pump();
      expect(sends, 1);
      expect(find.text('取消'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      response.complete(result);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.scripts.single, contains(jsonEncode(result.sdkResult)));
      if (result.sent) {
        expect(completed, result);
        expect(find.text('安全验证'), findsNothing);
        // A delayed SDK callback cannot pop the underlying page a second time.
        controller.emit({'type': 'complete', 'bizResult': true});
        await tester.pump();
        expect(find.text('open'), findsOneWidget);
      } else {
        expect(completed, isNull);
        expect(find.text('安全验证'), findsNothing);
        expect(platform.controllers.length, result.captchaVerified ? 2 : 1);
        if (result.captchaVerified) {
          platform.controllers.last.emit({'type': 'ready'});
          await tester.pump();
        }
        platform.controllers.last
            .emit({'type': 'close', 'reason': 'userDismiss'});
        await tester.pumpAndSettle();
      }
      EasyLoading.dismiss();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

Future<_Platform> _openRecoveryDialog(WidgetTester tester,
    Future<VerificationCodeResult> Function(String) request,
    {TargetPlatform platform = TargetPlatform.iOS,
    bool dark = false,
    ValueChanged<VerificationCodeResult?>? onClose}) async {
  final webview = _Platform();
  final previous = WebViewPlatform.instance;
  WebViewPlatform.instance = webview;
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await EasyLoading.dismiss();
    WebViewPlatform.instance = previous ?? _Platform();
    debugDefaultTargetPlatformOverride = null;
  });
  await tester.pumpWidget(MaterialApp(
      builder: EasyLoading.init(),
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () async {
                    final result = await showAliyunCaptcha(context, request);
                    onClose?.call(result);
                  },
                  child: const Text('open'))))));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return webview;
}
