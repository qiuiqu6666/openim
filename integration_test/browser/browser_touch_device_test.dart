import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openim_common/src/widgets/in_app_browser/in_app_browser.dart';
import 'package:openim_common/src/widgets/in_app_browser/in_app_browser_edge_drag.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native web buttons remain tappable across retained pages',
      (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('''<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Touch fixture ${request.uri.path}</title></head><body style="margin:0">
<button style="position:fixed;inset:0;width:100%;height:100%;font-size:24px"
 onclick="window.taps++;this.textContent='Taps '+window.taps">Tap web content</button>
<script>window.taps=0;</script></body></html>''');
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
    });
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => InAppBrowserHost(child: child!),
      home: const Scaffold(body: Text('Chat')),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<WebViewController> openPage(int index) async {
      await openInAppBrowser(
          Uri.parse('http://127.0.0.1:${server.port}/page$index'));
      await settle();
      final controller = WebViewController.fromPlatform(tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller);
      var ready = false;
      for (var i = 0; i < 100; i++) {
        final value =
            await controller.runJavaScriptReturningResult('typeof window.taps');
        if (value.toString().contains('number')) {
          ready = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ready, isTrue);
      await settle();
      return controller;
    }

    Future<void> tapWeb(WebViewController controller, int count) async {
      await tester.tap(find.byType(InAppBrowserEdgeDrag));
      await settle();
      expect(
          (await controller.runJavaScriptReturningResult('window.taps'))
              .toString(),
          '$count');
    }

    final first = await openPage(0);
    await tapWeb(first, 1);
    var firstTaps = 1;
    for (var i = 1; i <= 3; i++) {
      final next = await openPage(i);
      await tapWeb(next, 1);
      // Pull the real WebView down at its top, then restore the retained view.
      await tester.drag(
          find.byType(InAppBrowserEdgeDrag),
          Offset(
              0,
              tester.view.physicalSize.height /
                  tester.view.devicePixelRatio *
                  .4));
      await settle();
      expect(find.byTooltip('Expand page'), findsOneWidget);
      await tester.tap(find.byTooltip('Expand page'));
      await settle();
      await tapWeb(next, 2);
      Future<void> choosePage(String title) async {
        final pageContext = tester.element(find.byType(InAppBrowserPage));
        await tester
            .tapAt(Offset(10, MediaQuery.paddingOf(pageContext).top + 2));
        await settle();
        await tester.tap(find.byKey(const ValueKey('browser-page-count')));
        await settle();
        await tester.tap(find.widgetWithText(ListTile, title));
        await settle();
      }

      await choosePage('Touch fixture /page0');
      await tapWeb(first, ++firstTaps);
      await choosePage('Touch fixture /page$i');
      await tapWeb(next, 3);
      await tester.tap(find.text('Done'));
      await settle();
      await tester.tap(find.byTooltip('Expand page'));
      await settle();
      await tapWeb(first, ++firstTaps);
    }
    InAppBrowserHost.close();
    await settle();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
