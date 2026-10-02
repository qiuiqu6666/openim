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
