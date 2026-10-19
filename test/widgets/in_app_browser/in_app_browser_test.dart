import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/in_app_browser/in_app_browser.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _Platform extends WebViewPlatform {
  final controllers = <_Controller>[];
  final delegates = <_Delegate>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    final controller = _Controller(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
      PlatformNavigationDelegateCreationParams params) {
    final delegate = _Delegate(params);
    delegates.add(delegate);
    return delegate;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  Uri? loaded;
  bool back = false;
  String? title;
  @override
  Future<String?> getTitle() async => title;
  int backs = 0, reloads = 0;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loaded = params.uri;
  }

  @override
  Future<bool> canGoBack() async => back;
  @override
  Future<void> goBack() async {
    backs++;
    back = false;
  }

  @override
  Future<void> reload() async {
    reloads++;
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late PageEventCallback started, finished;
  late NavigationRequestCallback navigate;
  late WebResourceErrorCallback error;
  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {
    navigate = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    started = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}
  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async {}
  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    error = callback;
  }
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late _Platform platform;
  setUp(() {
    platform = _Platform();
    WebViewPlatform.instance = platform;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> open(WidgetTester tester, {bool dark = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () => openInAppBrowser(
                    Uri.parse('https://example.com'),
                    context: context),
                child: const Text('Open'),
              ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('web route loads internally and rejects app schemes',
      (tester) async {
    await open(tester);
    expect(
        platform.controllers.single.loaded, Uri.parse('https://example.com'));
    final delegate = platform.delegates.single;
    expect(
        await delegate.navigate(const NavigationRequest(
            url: 'https://other.example/path', isMainFrame: true)),
        NavigationDecision.navigate);
    for (final url in [
      'intent://app',
      'mailto:a@example.com',
      'file:///secret',
      'https://user:pass@example.com'
    ]) {
      expect(
          await delegate
              .navigate(NavigationRequest(url: url, isMainFrame: true)),
          NavigationDecision.prevent);
    }
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets(
      'back traverses web history; refresh preserves controller; back exits',
      (tester) async {
    await open(tester);
    final controller = platform.controllers.single..back = true;
    platform.delegates.single.finished('https://example.com');
    await tester.pump();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(controller.backs, 1);
    expect(find.byType(InAppBrowserPage), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(controller.reloads, 1);
    expect(platform.controllers.length, 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(InAppBrowserPage), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('timeout retries and ignores stale callbacks, dark=$dark',
        (tester) async {
      await open(tester, dark: dark);
      final old = platform.delegates.single;
      await tester.pump(const Duration(seconds: 31));
      old.finished('https://example.com');
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(platform.controllers.length, 2);
      old.error(const WebResourceError(
          errorCode: -1, description: 'stale', isForMainFrame: true));
      platform.delegates.last.finished('https://example.com');
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      old.finished('https://example.com');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows document names and clears old titles during navigation',
      (tester) async {
    await open(tester);
    expect(find.text('Web page'), findsOneWidget);
    expect(find.text('example.com'), findsNothing);
    final controller = platform.controllers.single;
    final delegate = platform.delegates.single;
    controller.title = '百度一下，你就知道';
    delegate.finished('https://example.com');
    await tester.pumpAndSettle();
    expect(find.text('百度一下，你就知道'), findsOneWidget);
    delegate.started('https://example.com/next');
    await tester.pump();
    expect(find.text('百度一下，你就知道'), findsNothing);
    controller.title = '   ';
    delegate.finished('https://example.com/next');
    await tester.pumpAndSettle();
    expect(find.text('Web page'), findsOneWidget);
    controller.title = 'https://example.com/next';
    delegate.finished('https://example.com/next');
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/next'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  });

  testWidgets('blue loading indicator loops until the page finishes',
      (tester) async {
    await open(tester);
    final indicator = find.byType(LinearProgressIndicator);
    expect(tester.widget<LinearProgressIndicator>(indicator).value, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(indicator, findsOneWidget);
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    expect(indicator, findsNothing);
    platform.delegates.single.started('https://example.com/next');
    await tester.pump();
    expect(indicator, findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  });

  testWidgets('unsupported platform and invalid URLs never launch externally',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await open(tester);
    expect(platform.controllers, isEmpty);
    expect(find.text('Embedded web pages are not supported on this platform.'),
        findsOneWidget);
    expect(await openInAppBrowser(Uri.parse('file:///test')), isFalse);
    expect(await openInAppBrowser(Uri.parse('https://user:pass@example.com')),
        isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS small screen with large text supports error recovery',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    final delegate = platform.delegates.single;
    delegate.error(const WebResourceError(
        errorCode: -1, description: 'image failed', isForMainFrame: false));
    await tester.pump();
    expect(find.text('Retry'), findsNothing);
    delegate.error(const WebResourceError(
        errorCode: -1, description: 'offline', isForMainFrame: true));
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
