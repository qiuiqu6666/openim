import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/widgets/aliyun_captcha_dialog.dart';
import 'package:openim/pages/mine/settings/widgets/aliyun_captcha_html.dart';

void main() {
  test('SDK loads from CDN with public config and raw proof bridge', () {
    final html = aliyunCaptchaHtml(language: 'cn');
    expect(html, contains("region:'sgp',prefix:'x8rp89e'"));
    expect(html, contains("SceneId:'11obe4txe'"));
    expect(html, contains('captchaVerifyParam:param'));
    expect(
        html,
        contains(
            'https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js'));
    expect(html, contains("mode:'popup'"));
    expect(html, isNot(contains('slideStyle')));
    expect(html, isNot(contains('#captcha-element{')));
    expect(html, contains("onClose:function(reason)"));
    expect(html, contains('window.captcha.show()'));
    expect(html, isNot(contains('rem:')));
    expect(html, isNot(contains('transform:')));
    expect(html, isNot(contains('zoom:')));
    expect(html, contains('2100'));
    expect(html, isNot(contains('AccessKey')));
  });
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 568), const Size(640, 360)]) {
      testWidgets('dialog fits $size dark=$dark and cancel never sends',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var called = false;
        await tester.pumpWidget(MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () =>
                            showAliyunCaptcha(context, (param) async {
                              called = true;
                              throw StateError('must not send');
                            }),
                        child: const Text('open'))))));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('安全验证'), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('取消'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(called, false);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
