import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/global_search/inline/inline_global_search_surface.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';
import 'package:openim_common/openim_common.dart';

class _Source extends GlobalSearchSource {
  final updates = StreamController<List<ConversationInfo>>.broadcast();
  Completer<List<FriendInfo>>? pending;
  int calls = 0;

  @override
  Stream<List<ConversationInfo>> get conversationUpdates => updates.stream;
  @override
  Future<List<FriendInfo>> friends(String query) async {
    calls++;
    return pending?.future ?? <FriendInfo>[];
  }

  @override
  Future<List<GroupInfo>> groups(String query) async => [];
  @override
  Future<List<ConversationInfo>> conversations(String query) async => [];
  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async =>
      [];
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

Future<void> _mount(
  WidgetTester tester, {
  required _Source source,
  required List<GlobalSearchLogic> searches,
  required List<bool> modes,
  required ScrollController scroll,
  required _Routes routes,
  bool dark = false,
  bool reducedMotion = false,
  Size size = const Size(375, 812),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      navigatorObservers: [routes],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 24, bottom: 34),
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: InlineGlobalSearchSurface(
        entryKey: const ValueKey('conversation-search-entry'),
        onSearchModeChanged: modes.add,
        createSearch: () {
          final search = GlobalSearchLogic(source: source);
          searches.add(search);
          return search;
        },
        feedBuilder: (searchPlaceholder) => Scaffold(
          appBar: AppBar(title: const Text('消息')),
          body: Column(children: [
            searchPlaceholder,
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: 80,
                itemBuilder: (_, index) => ListTile(title: Text('会话 $index')),
              ),
            ),
          ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

final _entry = find.byKey(const ValueKey('conversation-search-entry'));
final _input = find.byKey(const ValueKey('chat-history-search-input'));
final _cancel = find.byKey(const ValueKey('chat-history-search-cancel'));

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  for (final dark in [false, true]) {
    testWidgets(
        'search expands in current route and cancel restores feed ($dark)',
        (tester) async {
      final source = _Source();
      final searches = <GlobalSearchLogic>[];
      final modes = <bool>[];
      final scroll = ScrollController();
      final routes = _Routes();
      addTearDown(source.updates.close);
      addTearDown(scroll.dispose);
      await _mount(tester,
          source: source,
          searches: searches,
          modes: modes,
          scroll: scroll,
          routes: routes,
          dark: dark);
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      final entryY = tester.getTopLeft(_input).dy;
      final initialRect = tester.getRect(_entry);
      final inputState = tester.state(_input);
      final pushes = routes.pushes;
      await tester.tap(_entry);
      await tester.pump();
      expect(tester.getTopLeft(_input).dy, closeTo(entryY, 1));
      expect(tester.getRect(_entry), initialRect);
      expect(tester.state(_input), same(inputState));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getTopLeft(_input).dy, lessThan(entryY));
      expect(tester.getRect(_entry).width, lessThan(initialRect.width));
      expect(tester.state(_input), same(inputState));
      expect(find.byType(TextField), findsOneWidget);
      expect(
          tester
              .widgetList<Opacity>(
                  find.ancestor(of: _input, matching: find.byType(Opacity)))
              .every((w) => w.opacity == 1),
          isTrue);
      await tester.pumpAndSettle();
      expect(routes.pushes, pushes);
      expect(modes, [true]);
      expect(searches.single.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(source.updates.hasListener, isTrue);
      expect(find.text('消息'), findsNothing);
      expect(tester.getTopLeft(_entry).dy, closeTo(32, 1));
      final activeRect = tester.getRect(_entry);
      await tester.tap(_cancel);
      await tester.pump();
      expect(tester.getRect(_entry), activeRect);
      await tester.pump(const Duration(milliseconds: 150));
      final returningRect = tester.getRect(_entry);
      expect(returningRect.top, greaterThan(activeRect.top));
      expect(returningRect.top, lessThan(initialRect.top));
      expect(returningRect.width, greaterThan(activeRect.width));
      expect(returningRect.width, lessThan(initialRect.width));
      expect(tester.state(_input), same(inputState));
      await tester.pumpAndSettle();
      expect(_input, findsOneWidget);
      expect(tester.state(_input), same(inputState));
      expect(tester.getRect(_entry), initialRect);
      expect(tester.widget<TextField>(_input).readOnly, isTrue);
      expect(find.text('消息'), findsOneWidget);
      expect(scroll.offset, closeTo(offset, 1));
      expect(modes, [true, false]);
      expect(searches.single.isClosed, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(source.updates.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('back exits search; late requests and reentry are isolated',
      (tester) async {
    final source = _Source()..pending = Completer<List<FriendInfo>>();
    final searches = <GlobalSearchLogic>[];
    final modes = <bool>[];
    final scroll = ScrollController();
    final routes = _Routes();
    addTearDown(source.updates.close);
    addTearDown(scroll.dispose);
    await _mount(tester,
        source: source,
        searches: searches,
        modes: modes,
        scroll: scroll,
        routes: routes);
    await tester.tap(_entry);
    await tester.pumpAndSettle();
    await tester.enterText(_input, 'winter');
    await tester.pump(const Duration(milliseconds: 350));
    expect(source.calls, 1);
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('消息'), findsOneWidget);
    expect(searches.first.isClosed, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    source.pending!.complete([FriendInfo(userID: 'late', nickname: '迟到结果')]);
    await tester.pumpAndSettle();
    await tester.tap(_entry);
    await tester.pumpAndSettle();
    expect(searches, hasLength(2));
    expect(searches.last.searchCtrl.text, isEmpty);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.text('迟到结果'), findsNothing);
    expect(routes.pushes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(searches.last.isClosed, isTrue);
    expect(source.updates.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final systemBack in [false, true]) {
    testWidgets(
        'exit hides a keyboard left visible without focus ($systemBack)',
        (tester) async {
      final source = _Source();
      final searches = <GlobalSearchLogic>[];
      final scroll = ScrollController();
      addTearDown(source.updates.close);
      addTearDown(scroll.dispose);
      await _mount(tester,
          source: source,
          searches: searches,
          modes: [],
          scroll: scroll,
          routes: _Routes());
      await tester.tap(_entry);
      await tester.pumpAndSettle();
      await tester.enterText(_input, '好友');
      searches.single.focusNode.unfocus();
      await tester.pumpAndSettle();
      // Model an IME that remains visible after Flutter has lost focus.
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      expect(tester.testTextInput.isVisible, isTrue);
      if (systemBack) {
        await tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .maybePop();
      } else {
        await tester.tap(_cancel);
      }
      await tester.pumpAndSettle();
      expect(find.text('消息'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(_entry);
      await tester.pumpAndSettle();
      expect(searches.last.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('cancel during expansion reverses the same field without jumping',
      (tester) async {
    final source = _Source();
    final searches = <GlobalSearchLogic>[];
    final modes = <bool>[];
    final scroll = ScrollController();
    addTearDown(source.updates.close);
    addTearDown(scroll.dispose);
    await _mount(tester,
        source: source,
        searches: searches,
        modes: modes,
        scroll: scroll,
        routes: _Routes());
    final inputState = tester.state(_input);
    final origin = tester.getRect(_entry);
    await tester.tap(_entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final turning = tester.getRect(_entry);
    expect(turning.top, lessThan(origin.top));
    await tester.tap(_cancel);
    await tester.pump();
    expect(tester.getRect(_entry), turning);
    await tester.pump(const Duration(milliseconds: 60));
    final returning = tester.getRect(_entry);
    expect(returning.top, greaterThan(turning.top));
    expect(returning.width, greaterThan(turning.width));
    expect(tester.state(_input), same(inputState));
    await tester.pumpAndSettle();
    expect(tester.getRect(_entry), origin);
    expect(tester.state(_input), same(inputState));
    expect(tester.widget<TextField>(_input).readOnly, isTrue);
    expect(searches.single.isClosed, isTrue);
    expect(source.updates.hasListener, isFalse);
    expect(modes, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion, landscape and large text keep input usable',
      (tester) async {
    final source = _Source();
    final searches = <GlobalSearchLogic>[];
    final modes = <bool>[];
    final scroll = ScrollController();
    addTearDown(source.updates.close);
    addTearDown(scroll.dispose);
    await _mount(tester,
        source: source,
        searches: searches,
        modes: modes,
        scroll: scroll,
        routes: _Routes(),
        dark: true,
        reducedMotion: true,
        size: const Size(812, 375),
        scale: 2);
    await tester.tap(_entry);
    await tester.pump();
    final inputY = tester.getTopLeft(_input).dy;
    expect(inputY, inInclusiveRange(32, 40));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_input).dy, inputY);
    expect(searches.single.focusNode.hasFocus, isTrue);
    await tester.tap(_cancel);
    await tester.pumpAndSettle();
    expect(_entry, findsOneWidget);
    expect(modes, [true, false]);
    expect(tester.takeException(), isNull);
  });
}
