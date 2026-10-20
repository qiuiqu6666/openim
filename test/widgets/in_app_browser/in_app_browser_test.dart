import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

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
  bool forward = false;
  int forwards = 0;
  @override
  Future<bool> canGoForward() async => forward;
  @override
  Future<void> goForward() async {
    forwards++;
    forward = false;
  }

  String? title;
  String icon = '';
  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => icon;
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
    InAppBrowserShare.send = null;
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> open(WidgetTester tester,
      {bool dark = false, bool toast = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      builder: toast ? EasyLoading.init() : null,
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
    await tester.pump(const Duration(milliseconds: 500));
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
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('tapping exposed backdrop minimizes without losing web state',
      (tester) async {
    await open(tester);
    platform.controllers.single.title = 'Example website';
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(InAppBrowserPage));
    final top = tester.getTopLeft(find.byType(InAppBrowserPage)).dy;
    expect(top, greaterThan(0));
    await tester.tapAt(Offset(200, top / 2));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand page'), findsOneWidget);
    expect(find.text('Example website'), findsOneWidget);
    expect(find.byType(InAppBrowserPage), findsNothing);
    expect(tester.state(find.byType(InAppBrowserPage, skipOffstage: false)),
        same(state));
    await tester.tap(find.byTooltip('Expand page'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(InAppBrowserPage)), same(state));
    expect(platform.controllers, hasLength(1));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  testWidgets('minimized browser survives app route replacement and resumes',
      (tester) async {
    InAppBrowserHost.installBackHandler();
    final navigation = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigation,
      builder: (_, child) => InAppBrowserHost(child: child!),
      home: const Scaffold(
          key: ValueKey('underlying-chat'), body: Text('Original page')),
    ));
    await openInAppBrowser(Uri.parse('https://example.com'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final webController = platform.controllers.single;
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    final pageState = tester.state(find.byType(InAppBrowserPage));
    final gesture = await tester
        .startGesture(tester.getCenter(find.text('https://example.com')));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final beforeDock =
        tester.getSize(find.byKey(const ValueKey('underlying-chat'))).height;
    final dock = find.byKey(const ValueKey('browser-dock-surface'));
    expect(dock, findsOneWidget,
        reason:
            'The dock must already fill the reserved space before settling');
    final dockClip =
        find.ancestor(of: dock, matching: find.byType(ClipRect)).first;
    expect(tester.getRect(dockClip).top, lessThanOrEqualTo(beforeDock + 1));
    expect(
        tester.getRect(dockClip).bottom,
        closeTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio, 1));
    await tester.pumpAndSettle();
    final afterDock =
        tester.getSize(find.byKey(const ValueKey('underlying-chat'))).height;
    expect((beforeDock - afterDock).abs(), lessThan(2),
        reason: 'Settling into the dock must not abruptly resize the chat');
    expect(find.byTooltip('Expand page'), findsOneWidget);
    navigation.currentState!.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another page'))));
    await tester.pumpAndSettle();
    expect(find.text('Another page').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Expand page'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('browser-return-shortcut')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('browser-return-shortcut')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('browser-return-shortcut')), findsNothing);
    expect(tester.state(find.byType(InAppBrowserPage)), same(pageState));
    expect(platform.controllers.single, same(webController));
    expect(webController.reloads, 0);
    webController.back = true;
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(webController.backs, 1);
    expect(find.byType(InAppBrowserPage), findsOneWidget);
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Another page').hitTestable(), findsOneWidget);
    expect(find.byType(InAppBrowserPage, skipOffstage: false), findsNothing);
  });

  testWidgets('host keeps web view while an app share picker is visible',
      (tester) async {
    final navigation = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigation,
      builder: (_, child) => InAppBrowserHost(child: child!),
      home: const Scaffold(body: Text('Home')),
    ));
    InAppBrowserShare.send = (_, __) async {
      await navigation.currentState!.push(MaterialPageRoute<void>(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel sharing')))));
      return 0;
    };
    await openInAppBrowser(Uri.parse('https://example.com'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(InAppBrowserPage));
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel sharing').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Cancel sharing'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(InAppBrowserPage)), same(state));
    InAppBrowserHost.close();
    await tester.pumpAndSettle();
    expect(find.byType(InAppBrowserPage, skipOffstage: false), findsNothing);
  });

  testWidgets('share delegates current link in app and prevents duplicate taps',
      (tester) async {
    final pending = Completer<int>();
    var calls = 0;
    Uri? shared;
    InAppBrowserShare.send = (uri, title) {
      calls++;
      shared = uri;
      return pending.future;
    };
    await open(tester, toast: true);
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    await tester.tap(find.byTooltip('Share'));
    expect(calls, 1);
    expect(shared, Uri.parse('https://example.com'));
    pending.complete(1);
    await tester.pumpAndSettle();
    expect(find.text('Shared'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(
        tester.getCenter(find.text('Shared')).dy,
        closeTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
            20));
    expect(find.byType(InAppBrowserPage), findsOneWidget);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  for (final getRoute in [false, true]) {
    testWidgets(
        'background recedes and restores without rebuild, GetX=$getRoute',
        (tester) async {
      const background = ValueKey('browser-background');
      var builds = 0;
      Widget page(BuildContext context) {
        builds++;
        return Scaffold(
          key: background,
          body: TextButton(
            onPressed: () => openInAppBrowser(Uri.parse('https://example.com'),
                context: context),
            child: const Text('Open'),
          ),
        );
      }

      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (_) => getRoute
            ? GetPageRoute<void>(page: () => Builder(builder: page))
            : MaterialPageRoute<void>(builder: page),
      ));
      final before = tester.getRect(find.byKey(background));
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final midway = tester.getRect(find.byKey(background));
      final sheetMidway = tester.getTopLeft(find.byType(InAppBrowserPage));
      expect(midway.width, lessThan(before.width));
      await tester.pump(const Duration(milliseconds: 350));
      final after = tester.getRect(find.byKey(background));
      expect(after.width, lessThan(before.width));
      expect(after.width, lessThan(midway.width));
      expect(sheetMidway.dy,
          greaterThan(tester.getTopLeft(find.byType(InAppBrowserPage)).dy));
      expect(after.top,
          lessThan(tester.getTopLeft(find.byType(InAppBrowserPage)).dy));
      expect(after.left, greaterThan(before.left));
      final openBuilds = builds;
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(background)), before);
      expect(builds, openBuilds);
    });
  }

  testWidgets('sheet minimizes, preserves web state, restores and closes',
      (tester) async {
    await open(tester);
    platform.controllers.single.back = true;
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    final sheet = find.byType(InAppBrowserPage);
    final initial = tester.getTopLeft(sheet).dy;
    var gesture = await tester
        .startGesture(tester.getCenter(find.text('https://example.com')));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    final dragStart = tester.getTopLeft(sheet).dy;
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(tester.getTopLeft(sheet).dy, closeTo(dragStart + 60, 2));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, closeTo(initial, 1));
    gesture = await tester
        .startGesture(tester.getCenter(find.text('https://example.com')));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 240));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(platform.controllers.single.backs, 0);
    expect(find.byType(InAppBrowserPage, skipOffstage: false), findsOneWidget);
    expect(find.byTooltip('Expand page'), findsOneWidget);
    expect(find.text('Open').hitTestable(), findsOneWidget);
    gesture =
        await tester.startGesture(tester.getCenter(find.text('example.com')));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    final restoringTop = tester.getTopLeft(sheet).dy;
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(tester.getTopLeft(sheet).dy, closeTo(restoringTop - 40, 2));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand page'), findsOneWidget);
    expect(sheet, findsNothing);
    gesture =
        await tester.startGesture(tester.getCenter(find.text('example.com')));
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -240));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    expect(platform.controllers, hasLength(1));
    expect(tester.getTopLeft(sheet).dy, closeTo(initial, 1));
    gesture = await tester
        .startGesture(tester.getCenter(find.text('https://example.com')));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 240));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close page'));
    await tester.pumpAndSettle();
    expect(find.byType(InAppBrowserPage, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('address editing validates links and reuses web history',
      (tester) async {
    await open(tester);
    platform.delegates.single.finished('https://example.com');
    await tester.pumpAndSettle();
    final controller = platform.controllers.single;
    await tester.tap(find.text('https://example.com'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'javascript:alert(1)');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(controller.loaded, Uri.parse('https://example.com'));
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' www.baidu.com/path ');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(controller.loaded, Uri.parse('https://www.baidu.com/path'));
    expect(platform.controllers.length, 1);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(InAppBrowserPage), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('timeout retries and ignores stale callbacks, dark=$dark',
        (tester) async {
      await open(tester, dark: dark);
      final depth = find.byKey(const ValueKey('browser-depth-background'));
      expect(tester.widget<ColoredBox>(depth).color,
          Theme.of(tester.element(depth)).colorScheme.scrim);
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
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      old.finished('https://example.com');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sheet shows current address and Done closes with web history',
      (tester) async {
    await open(tester);
    expect(find.text('https://example.com'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(InAppBrowserPage)).dy, greaterThan(0));
    final controller = platform.controllers.single..back = true;
    controller.forward = true;
    final delegate = platform.delegates.single;
    delegate.started('https://example.com/next');
    delegate.finished('https://example.com/next');
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/next'), findsOneWidget);
    await tester.tap(find.byTooltip('Forward'));
    await tester.pump();
    expect(controller.forwards, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(InAppBrowserPage), findsNothing);
    expect(controller.backs, 0);
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
    await tester.tap(find.text('Done'));
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
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
