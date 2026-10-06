import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;
import 'package:openim/pages/chat/favorites/favorite_picker_sheet.dart';
import 'package:openim/pages/chat/favorites/widgets/favorite_picker_content.dart';
import 'package:openim/pages/favorites/media/favorite_item_thumbnail.dart';
import 'package:openim/pages/mine/secondary/favorite_detail_page.dart';
import 'package:openim/pages/mine/secondary/favorite_note_edit_page.dart';
import 'package:openim/pages/mine/secondary/favorites_page.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:openim/services/favorite_send_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _item = FavoriteItem(
  id: 'favorite_1',
  kind: FavoriteKind.note,
  title: '会议安排',
  summary: '周五开会',
  version: 1,
  status: FavoriteStatus.ready,
  content: FavoriteContent(
      kind: FavoriteKind.note,
      blocks: [FavoriteBlock(id: 'b1', type: 'text', text: '周五开会')]),
);
const _target =
    FavoriteTarget(conversationID: 'c_a', userID: 'a', displayName: '张三');

FavoriteItem get _audioItem => FavoriteItem(
        id: 'voice_1',
        kind: FavoriteKind.audio,
        title: '测试123123123',
        version: 1,
        status: FavoriteStatus.ready,
        createdAt: DateTime(2026, 10, 5, 5, 48),
        assets: const [
          FavoriteAsset(
              id: 'voice-original',
              mimeType: 'audio/mp4',
              sizeBytes: 10,
              sha256:
                  '0000000000000000000000000000000000000000000000000000000000000000',
              durationMs: 7000)
        ]);

class _Repository extends FavoriteRepository {
  _Repository({List<FavoriteItem> initial = const [_item]})
      : values = List.of(initial),
        super(
            api: FavoriteApi(
                client: Dio(),
                baseUrl: 'https://favorites.invalid',
                tokenProvider: () => 'test-token'),
            userIDProvider: () => 'test-user',
            cacheEnabled: false);
  final List<FavoriteItem> values;
  final List<({String? query, FavoriteKind? kind, String? tagID})> requests =
      [];
  final List<FavoriteTag> labels = [
    const FavoriteTag(id: 'work', name: '工作'),
    const FavoriteTag(id: 'travel', name: '旅行')
  ];
  final List<({String id, List<String> tags})> tagUpdates = [];
  bool active = true;
  bool more = false;
  int pages = 0;
  String _query = '';
  FavoriteKind? _kind;
  String? _tagID;
  int archives = 0;
  int links = 0;
  int details = 0;
  int tagRequests = 0;

  @override
  bool get available => active;
  @override
  Future<FavoriteQuota> ensureCapabilities({bool force = false}) async =>
      const FavoriteQuota(supportsFavorites: true, supportsPrepareSend: true);
  @override
  Future<void> requireAvailable() async {
    if (!active) throw const FavoriteApiException('SESSION_CHANGED', '登录状态已改变');
  }

  @override
  List<FavoriteItem> get items => List.unmodifiable(values);
  @override
  String get sessionScope => 'test-session';
  @override
  bool isSessionCurrent(String scope) => active && scope == 'test-session';
  @override
  bool get hasMore => more;
  @override
  String get query => _query;
  @override
  FavoriteKind? get filterKind => _kind;
  @override
  String? get filterTagID => _tagID;
  @override
  List<FavoriteTag> get tags => List.unmodifiable(labels);
  @override
  Future<void> refreshTags() async {
    tagRequests++;
    notifyListeners();
  }

  @override
  Future<void> refresh(
      {String? query, FavoriteKind? kind, String? tagID}) async {
    requests.add((query: query, kind: kind, tagID: tagID));
    _query = query ?? _query;
    _kind = kind;
    _tagID = tagID;
    notifyListeners();
  }

  @override
  Future<FavoriteItem> getDetail(String id) async {
    details++;
    return values.firstWhere((item) => item.id == id);
  }

  @override
  Future<FavoriteItem> retryArchive(String id,
      {String? clientRequestID}) async {
    archives++;
    return _item;
  }

  @override
  Future<FavoriteItem> updateTags(String id, List<String> tagIDs,
      {int? expectedVersion, String? clientRequestID}) async {
    tagUpdates.add((id: id, tags: List.of(tagIDs)));
    return values.firstWhere((item) => item.id == id);
  }

  @override
  Future<FavoriteTag> createTag(String name, {String? clientRequestID}) async {
    final tag = FavoriteTag(id: 'tag_${labels.length}', name: name);
    labels.add(tag);
    notifyListeners();
    return tag;
  }

  @override
  Future<FavoriteItem> createLink(String url,
      {String title = '', String? clientRequestID}) async {
    links++;
    return _item;
  }

  @override
  Future<void> loadMore() async {
    pages++;
    more = false;
    notifyListeners();
  }
}

class _PendingListRequest {
  _PendingListRequest(this.kind, this.cancelToken);
  final FavoriteKind? kind;
  final CancelToken? cancelToken;
  final result = Completer<FavoritePage>();
}

/// Keep the real repository's filtering, cancellation and generation guards.
/// Only the API response timing is controlled by this fixture.
class _DelayedListApi extends FavoriteApi {
  _DelayedListApi(this.initial)
      : super(
            baseUrl: 'https://favorites.invalid',
            tokenProvider: () => 'test-token');
  final List<FavoriteItem> initial;
  final pending = <_PendingListRequest>[];
  bool delayed = false;
  int listCalls = 0;
  int detailCalls = 0;

  @override
  Future<FavoriteQuota> getQuota({CancelToken? cancelToken}) async =>
      const FavoriteQuota(supportsFavorites: true, supportsPrepareSend: true);

  @override
  Future<FavoritePage> list(
      {String query = '',
      FavoriteKind? kind,
      String? tagID,
      String? cursor,
      int? baseline,
      int limit = 30,
      CancelToken? cancelToken}) {
    listCalls++;
    if (!delayed) return Future.value(FavoritePage(items: initial));
    final request = _PendingListRequest(kind, cancelToken);
    pending.add(request);
    return request.result.future;
  }

  @override
  Future<FavoriteItem> getDetail(String id, {CancelToken? cancelToken}) async {
    detailCalls++;
    return initial.firstWhere((item) => item.id == id);
  }
}

Widget _host(Widget child,
        {bool dark = false,
        double scale = 1,
        bool disableAnimations = true,
        Color? progressColor,
        GlobalKey? previewKey}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) {
        final app = MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate
          ],
          theme: ThemeData(
              fontFamily: _exportPreview ? 'FavoritePickerPreviewFont' : null,
              brightness: dark ? Brightness.dark : Brightness.light,
              progressIndicatorTheme:
                  ProgressIndicatorThemeData(color: progressColor)),
          builder: EasyLoading.init(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: disableAnimations),
                  child: child!)),
          home: child,
        );
        return previewKey == null
            ? app
            : RepaintBoundary(key: previewKey, child: app);
      },
    );

Widget _launcher(FavoriteRepository repository,
        Future<FavoriteSendResult> Function(FavoriteItem) send,
        {Future<FavoriteSendResult> Function(String)? reconcile,
        FavoriteTarget target = _target}) =>
    Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => FavoritePickerSheet.show(context,
                    repository: repository,
                    target: target,
                    onSend: send,
                    onReconcile: reconcile),
                child: const Text('打开收藏'))));

({Rect sheet, Rect list}) _pickerBounds(WidgetTester tester) => (
      sheet: tester.getRect(find.byType(FavoritePickerSheet)),
      list: tester.getRect(find.byKey(const ValueKey('favorites-list')))
    );

void _expectPickerBounds(
        WidgetTester tester, ({Rect sheet, Rect list}) expected) =>
    expect(_pickerBounds(tester), expected);

Future<void> _choosePickerKind(WidgetTester tester, FavoriteKind kind) async {
  final chip = find.byKey(ValueKey('favorite-filter-${kind.name}'));
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    if (_exportPreview) await _loadPreviewFonts();
  });

  testWidgets('send button submits once and closes on success', (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    final result = Completer<FavoriteSendResult>();
    var calls = 0;
    await tester.pumpWidget(_host(
        _launcher(repository, (_) {
          calls++;
          return result.future;
        }),
        progressColor: Colors.white));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pump();
    expect(
        Theme.of(tester.element(find.byType(CircularProgressIndicator)))
            .progressIndicatorTheme
            .color,
        AppTokens.accent);
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    expect(calls, 1);
    result
        .complete(const FavoriteSendResult(status: FavoriteSendStatus.success));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritePickerSheet), findsNothing);
  });

  testWidgets('open picker keeps its sender when the widget target changes',
      (tester) async {
    final repository = _Repository();
    final target = ValueNotifier(_target);
    addTearDown(repository.dispose);
    addTearDown(target.dispose);
    final destinations = <String>[];
    await tester.pumpWidget(_host(Scaffold(
        body: ValueListenableBuilder<FavoriteTarget>(
            valueListenable: target,
            builder: (_, destination, __) => FavoritePickerSheet(
                repository: repository,
                target: destination,
                onSend: (_) async {
                  destinations.add(destination.conversationID);
                  return const FavoriteSendResult(
                      status: FavoriteSendStatus.failed,
                      errorCode: 'CANCELLED');
                })))));
    await tester.pumpAndSettle();
    target.value = const FavoriteTarget(
        conversationID: 'c_b', userID: 'b', displayName: '李四');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    expect(destinations, ['c_a']);
  });

  testWidgets('picker search opens on demand and clearing it queries again',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(_launcher(
        repository,
        (_) async =>
            const FavoriteSendResult(status: FavoriteSendStatus.success))));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorites-search')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('favorites-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorites-search')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('favorites-search')), '会议');
    await tester.pump(const Duration(milliseconds: 301));
    expect(repository.requests.last.query, '会议');
    await tester.tap(find.byKey(const ValueKey('favorites-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorites-search')), findsNothing);
    expect(repository.requests.last.query, '');
  });

  testWidgets('picker management opens the existing page and returns safely',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(_launcher(
        repository,
        (_) async =>
            const FavoriteSendResult(status: FavoriteSendStatus.success))));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-manage')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(FavoritesPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(FavoritePickerSheet), findsOneWidget);
    expect(
        find.byKey(const ValueKey('favorite-send-favorite_1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        '99chat picker uses compact cards and real metadata in '
        '${dark ? 'dark' : 'light'} theme', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository(initial: [
        FavoriteItem(
          id: 'favorite_1',
          kind: FavoriteKind.note,
          title: '会议安排',
          summary: '周五开会',
          version: 1,
          status: FavoriteStatus.ready,
          createdAt: DateTime(2026, 10, 4, 8, 23),
          source: const FavoriteSource(displayName: '秋'),
          content: _item.content,
        ),
        _audioItem,
      ]);
      addTearDown(repository.dispose);
      final previewKey = GlobalKey();
      await tester.pumpWidget(_host(
          _launcher(
              repository,
              (_) async =>
                  const FavoriteSendResult(status: FavoriteSendStatus.success)),
          dark: dark,
          previewKey: previewKey));
      await tester.tap(find.text('打开收藏'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(FavoritePickerSheet)).height,
          closeTo(812 * .78, .01));
      expect(
          tester.getSize(find.byKey(const ValueKey('favorite-picker-handle'))),
          const Size(38, 5));
      final title = tester.widget<Text>(find.text('收藏'));
      expect(title.style?.fontSize, 24);
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(find.text('发送到：张三'), findsNothing);
      expect(find.text('点击收藏查看或播放，右侧按钮发送'), findsNothing);
      expect(find.text('来源：秋'), findsOneWidget);
      expect(find.text('2026-10-04 08:23'), findsOneWidget);
      expect(find.text('2026/10/04'), findsNothing);
      final card = tester.widget<Material>(find
          .descendant(
              of: find.byKey(const ValueKey('favorite-favorite_1')),
              matching: find.byType(Material))
          .first);
      expect(
          card.color, dark ? const Color(0xFF252A33) : const Color(0xFFF6F8FB));
      expect(card.borderRadius, BorderRadius.circular(16));
      final all = tester.widget<ChoiceChip>(
          find.byKey(const ValueKey('favorite-filter-all')));
      expect(all.shape, isA<StadiumBorder>());
      expect((all.label as Text).data, '全部 (2)');
      final voiceThumbnail = find.descendant(
          of: find.byKey(const ValueKey('favorite-voice_1')),
          matching: find.byType(FavoriteItemThumbnail));
      final audioSize = tester.getSize(voiceThumbnail);
      expect(audioSize.width, greaterThanOrEqualTo(120));
      expect(audioSize.width, greaterThan(audioSize.height * 2));
      expect(find.text('7″'), findsOneWidget);
      expect(repository.details, 0);
      for (final id in ['favorite_1', 'voice_1']) {
        expect(find.byKey(ValueKey('favorite-picker-menu-$id')), findsNothing);
        expect(
            find.descendant(
                of: find.byKey(ValueKey('favorite-$id')),
                matching: find.byType(IconButton)),
            findsOneWidget);
      }
      if (_exportPreview) {
        await _export(tester, previewKey, dark ? 'dark' : 'light');
      }
    });

    testWidgets(
        'delayed picker category replacement keeps sheet and list bounds in '
        '${dark ? 'dark' : 'light'} theme', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final api = _DelayedListApi([_item, _audioItem]);
      final repository = FavoriteRepository(
          api: api, userIDProvider: () => 'switch-user', cacheEnabled: false);
      addTearDown(repository.dispose);
      await tester.pumpWidget(_host(
          _launcher(
              repository,
              (_) async =>
                  const FavoriteSendResult(status: FavoriteSendStatus.success)),
          dark: dark));
      await tester.tap(find.text('打开收藏'));
      await tester.pumpAndSettle();
      expect(repository.items, hasLength(2));
      final bounds = _pickerBounds(tester);
      api.delayed = true;
      await _choosePickerKind(tester, FavoriteKind.audio);
      expect(api.pending.single.kind, FavoriteKind.audio);
      expect(repository.loading, isTrue);
      _expectPickerBounds(tester, bounds);
      await tester.pump(const Duration(milliseconds: 100));
      _expectPickerBounds(tester, bounds);

      api.pending.single.result.complete(FavoritePage(items: [_audioItem]));
      await tester.pumpAndSettle();
      _expectPickerBounds(tester, bounds);
      expect(find.byKey(const ValueKey('favorite-voice_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('favorite-favorite_1')), findsNothing);
      expect(api.listCalls, 2);
      expect(api.detailCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'empty picker category preserves sheet and list bounds in '
        '${dark ? 'dark' : 'light'} theme', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final api = _DelayedListApi([_item, _audioItem]);
      final repository = FavoriteRepository(
          api: api,
          userIDProvider: () => 'empty-switch-user',
          cacheEnabled: false);
      addTearDown(repository.dispose);
      final previewKey = GlobalKey();
      await tester.pumpWidget(_host(
          _launcher(
              repository,
              (_) async =>
                  const FavoriteSendResult(status: FavoriteSendStatus.success)),
          dark: dark,
          previewKey: previewKey));
      await tester.tap(find.text('打开收藏'));
      await tester.pumpAndSettle();
      final bounds = _pickerBounds(tester);
      api.delayed = true;
      await _choosePickerKind(tester, FavoriteKind.image);
      _expectPickerBounds(tester, bounds);
      api.pending.single.result.complete(const FavoritePage(items: []));
      await tester.pumpAndSettle();
      _expectPickerBounds(tester, bounds);
      expect(find.text('没有匹配的收藏'), findsOneWidget);
      expect(find.byKey(const ValueKey('favorite-voice_1')), findsNothing);
      expect(find.byKey(const ValueKey('favorite-favorite_1')), findsNothing);
      expect(api.listCalls, 2);
      expect(tester.takeException(), isNull);
      if (_exportPreview) {
        await _export(tester, previewKey, dark ? 'empty-dark' : 'empty-light');
      }
    });
  }

  testWidgets(
      'rapid category switching ignores obsolete results without changing bounds',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final api = _DelayedListApi([_item, _audioItem]);
    final repository = FavoriteRepository(
        api: api,
        userIDProvider: () => 'rapid-switch-user',
        cacheEnabled: false);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(
        _launcher(
            repository,
            (_) async =>
                const FavoriteSendResult(status: FavoriteSendStatus.success)),
        disableAnimations: false));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    final bounds = _pickerBounds(tester);
    api.delayed = true;
    await _choosePickerKind(tester, FavoriteKind.audio);
    _expectPickerBounds(tester, bounds);
    await _choosePickerKind(tester, FavoriteKind.image);
    _expectPickerBounds(tester, bounds);
    expect(api.pending.map((request) => request.kind),
        [FavoriteKind.audio, FavoriteKind.image]);
    expect(api.pending.first.cancelToken?.isCancelled, isTrue);

    api.pending.last.result.complete(const FavoritePage(items: []));
    await tester.pumpAndSettle();
    _expectPickerBounds(tester, bounds);
    expect(find.text('没有匹配的收藏'), findsOneWidget);
    api.pending.first.result.complete(FavoritePage(items: [_audioItem]));
    await tester.pumpAndSettle();
    _expectPickerBounds(tester, bounds);
    expect(repository.filterKind, FavoriteKind.image);
    expect(repository.items, isEmpty);
    expect(find.text('没有匹配的收藏'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-voice_1')), findsNothing);
    expect(api.listCalls, 3);
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
        'category replacement ${reducedMotion ? 'respects reduced motion' : 'fades smoothly'} with one mounted list',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _DelayedListApi([_item, _audioItem]);
      final repository = FavoriteRepository(
          api: api, userIDProvider: () => 'fade-user', cacheEnabled: false);
      addTearDown(repository.dispose);
      await tester.pumpWidget(_host(
          _launcher(
              repository,
              (_) async =>
                  const FavoriteSendResult(status: FavoriteSendStatus.success)),
          disableAnimations: reducedMotion));
      await tester.tap(find.text('打开收藏'));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('favorites-list'));
      final controller = tester.widget<ListView>(list).controller;
      final content = find.byType(FavoritePickerContent);
      final fade =
          find.descendant(of: content, matching: find.byType(FadeTransition));
      expect(fade, findsOneWidget);
      api.delayed = true;
      await _choosePickerKind(tester, FavoriteKind.audio);
      api.pending.single.result.complete(FavoritePage(items: [_audioItem]));
      await tester.pump();
      expect(list, findsOneWidget);
      expect(tester.widget<ListView>(list).controller, same(controller));
      final opacity = tester.widget<FadeTransition>(fade).opacity;
      if (reducedMotion) {
        expect(opacity.value, 1);
      } else {
        expect(opacity.value, lessThan(1));
        await tester.pump(const Duration(milliseconds: 40));
        expect(opacity.value, greaterThan(0));
        expect(opacity.value, lessThan(1));
      }
      await tester.pumpAndSettle();
      expect(opacity.value, 1);
      expect(list, findsOneWidget);
      expect(tester.widget<ListView>(list).controller, same(controller));
      expect(find.byKey(const ValueKey('favorite-voice_1')), findsOneWidget);
      expect(api.listCalls, 2);
      expect(api.detailCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('picker marks loaded counts as partial while more pages exist',
      (tester) async {
    final repository = _Repository()..more = true;
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(_launcher(
        repository,
        (_) async =>
            const FavoriteSendResult(status: FavoriteSendStatus.success))));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    final all = tester
        .widget<ChoiceChip>(find.byKey(const ValueKey('favorite-filter-all')));
    expect((all.label as Text).data, '全部 (1+)');
    expect(find.text('已显示全部收藏'), findsNothing);
    expect(find.byKey(const ValueKey('favorites-load-more')), findsOneWidget);
  });

  testWidgets('small picker search stays usable above the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(
        _launcher(
            repository,
            (_) async =>
                const FavoriteSendResult(status: FavoriteSendStatus.success)),
        scale: 1.3));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-search-toggle')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final search = find.byKey(const ValueKey('favorites-search'));
    expect(tester.getBottomRight(search).dy, lessThanOrEqualTo(268));
    expect(tester.getSize(find.byKey(const ValueKey('favorites-list'))).height,
        greaterThan(24));
    await tester.enterText(search, '会议');
    await tester.pump(const Duration(milliseconds: 301));
    expect(repository.requests.last.query, '会议');
    expect(tester.takeException(), isNull);
  });

  testWidgets('row previews read-only content and only the send button sends',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    var calls = 0;
    await tester.pumpWidget(_host(_launcher(repository, (_) async {
      calls++;
      return const FavoriteSendResult(status: FavoriteSendStatus.success);
    })));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorite-preview-favorite_1')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('favorite-favorite_1')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteDetailPage), findsOneWidget);
    expect(find.text('周五开会'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-detail-send')), findsNothing);
    expect(find.byKey(const ValueKey('favorite-detail-edit')), findsNothing);
    expect(calls, 0);
    Navigator.of(tester.element(find.byType(FavoriteDetailPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(FavoritePickerSheet), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(FavoritePickerSheet), findsNothing);
  });

  testWidgets(
      'unavailable original disables send but still permits read-only preview',
      (tester) async {
    const failed = FavoriteItem(
        id: 'favorite_1',
        kind: FavoriteKind.note,
        title: '会议安排',
        version: 1,
        status: FavoriteStatus.failed,
        content: FavoriteContent(
            kind: FavoriteKind.note,
            blocks: [FavoriteBlock(id: 'b1', type: 'text', text: '周五开会')]));
    final repository = _Repository(initial: [failed]);
    addTearDown(repository.dispose);
    var calls = 0;
    await tester.pumpWidget(_host(_launcher(repository, (_) async {
      calls++;
      return const FavoriteSendResult(status: FavoriteSendStatus.success);
    })));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('favorite-send-favorite_1')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('favorite-favorite_1')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteDetailPage), findsOneWidget);
    expect(find.text('周五开会'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-detail-send')), findsNothing);
    expect(find.byKey(const ValueKey('favorite-detail-retry-archive')),
        findsNothing);
    expect(calls, 0);
    expect(repository.archives, 0);
  });

  testWidgets('explicit failure keeps picker available for same-item retry',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    var calls = 0;
    await tester.pumpWidget(_host(_launcher(repository, (_) async {
      calls++;
      return const FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          errorMessage: '暂时无法发送',
          retryable: true);
    })));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法发送'), findsOneWidget);
    expect(find.byType(FavoritePickerSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets(
      'unknown send locks another submission until destination is checked',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    var calls = 0;
    await tester.pumpWidget(_host(_launcher(repository, (_) async {
      calls++;
      return const FavoriteSendResult(status: FavoriteSendStatus.unknown);
    })));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('发送状态待确认'), findsOneWidget);
  });

  testWidgets('management opens detail and only explicit send calls sender',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    var calls = 0;
    await tester.pumpWidget(_host(FavoritesPage(
        repository: repository,
        onSendToConversation: (_) async {
          calls++;
          return const FavoriteSendResult(
              status: FavoriteSendStatus.failed, errorCode: 'CANCELLED');
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-favorite_1')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteDetailPage), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('favorite-detail-send')));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('search debounces final query and filters query the repository',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(FavoritesPage(repository: repository)));
    await tester.pumpAndSettle();
    final initial = repository.requests.length;
    await tester.enterText(find.byKey(const ValueKey('favorites-search')), '合');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
        find.byKey(const ValueKey('favorites-search')), '合同');
    await tester.pump(const Duration(milliseconds: 301));
    expect(repository.requests.length, initial + 1);
    expect(repository.requests.last.query, '合同');
    await tester.tap(find.byKey(const ValueKey('favorite-filter-image')));
    await tester.pumpAndSettle();
    expect(repository.requests.last.kind, FavoriteKind.image);
    expect(repository.requests.last.query, '合同');
  });

  testWidgets(
      'P0 collection hides unopened filters and tag operations without requesting tags',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(FavoritesPage(repository: repository)));
    await tester.pumpAndSettle();
    for (final name in ['location', 'contact', 'messageBundle', 'unknown']) {
      expect(find.byKey(ValueKey('favorite-filter-$name')), findsNothing);
    }
    expect(find.byKey(const ValueKey('favorites-manage-tags')), findsNothing);
    expect(find.byKey(const ValueKey('favorites-tag-filter')), findsNothing);
    expect(repository.tagRequests, 0);
    expect(
        repository.requests.every((request) => request.tagID == null), isTrue);
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pump();
    expect(find.byKey(const ValueKey('favorites-tag-selected')), findsNothing);
  });

  testWidgets('search sends at most 64 characters to the real query boundary',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(FavoritesPage(repository: repository)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('favorites-search')),
        List.filled(80, '字').join());
    await tester.pump(const Duration(milliseconds: 301));
    expect(repository.requests.last.query?.length, 64);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('favorites-search')))
            .controller
            ?.text
            .length,
        64);
  });

  testWidgets('failed note save keeps entered text and retry succeeds',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(_host(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => FavoriteNoteEditPage(onSave: (_) async {
                              attempts++;
                              if (attempts == 1) {
                                throw const FavoriteApiException(
                                    'TEMPORARY_UNAVAILABLE', '暂时无法保存');
                              }
                            }))),
                child: const Text('新建笔记'))))));
    await tester.tap(find.text('新建笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留这段文字');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.byType(FavoriteNoteEditPage), findsOneWidget);
    expect(find.text('保留这段文字'), findsOneWidget);
    expect(find.text('暂时无法保存'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteNoteEditPage), findsNothing);
    expect(attempts, 2);
  });

  testWidgets('picker remains bounded in dark landscape with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(
        _launcher(
            repository,
            (_) async =>
                const FavoriteSendResult(status: FavoriteSendStatus.success)),
        dark: true,
        scale: 1.5));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(FavoritePickerSheet), findsOneWidget);
  });

  testWidgets(
      'unknown result uses query-only reconciliation before remaining sends',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    var sends = 0;
    final attempts = <String>[];
    await tester.pumpWidget(_host(_launcher(repository, (_) async {
      sends++;
      return sends == 1
          ? const FavoriteSendResult(
              status: FavoriteSendStatus.unknown, sendAttemptID: 'attempt-1')
          : const FavoriteSendResult(status: FavoriteSendStatus.success);
    }, reconcile: (id) async {
      attempts.add(id);
      return const FavoriteSendResult(
          status: FavoriteSendStatus.failed, errorCode: 'PARTIAL_READY');
    })));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-reconcile')));
    await tester.pumpAndSettle();
    expect(attempts, ['attempt-1']);
    expect(sends, 1);
    expect(find.textContaining('继续发送剩余内容'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-send-favorite_1')));
    await tester.pumpAndSettle();
    expect(sends, 2);
    expect(find.byType(FavoritePickerSheet), findsNothing);
  });

  testWidgets(
      'batch failure preserves all selected items for a safe continuation',
      (tester) async {
    const second = FavoriteItem(
        id: 'favorite_2',
        kind: FavoriteKind.text,
        title: '第二条',
        version: 1,
        status: FavoriteStatus.ready,
        content: FavoriteContent(
            kind: FavoriteKind.text,
            blocks: [FavoriteBlock(id: 'b2', type: 'text', text: '第二条')]));
    final repository = _Repository(initial: [_item, second]);
    addTearDown(repository.dispose);
    final sent = <List<String>>[];
    await tester.pumpWidget(_host(FavoritesPage(
        repository: repository,
        onSendItemsToConversation: (items) async {
          sent.add(items.map((item) => item.id).toList());
          return sent.length == 1
              ? const FavoriteSendResult(
                  status: FavoriteSendStatus.failed,
                  sentCount: 1,
                  totalCount: 2,
                  retryable: true)
              : const FavoriteSendResult(
                  status: FavoriteSendStatus.success,
                  sentCount: 2,
                  totalCount: 2);
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorite-favorite_1')));
    await tester.tap(find.byKey(const ValueKey('favorite-favorite_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-send-selected')));
    await tester.pumpAndSettle();
    expect(find.textContaining('再次点击发送继续未完成部分'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorites-send-selected')));
    await tester.pumpAndSettle();
    expect(sent, [
      ['favorite_1', 'favorite_2'],
      ['favorite_1', 'favorite_2']
    ]);
    expect(find.byKey(const ValueKey('favorites-send-selected')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('failed archive retries saving before enabling send',
      (tester) async {
    const failed = FavoriteItem(
        id: 'favorite_1',
        kind: FavoriteKind.note,
        title: '会议安排',
        version: 1,
        status: FavoriteStatus.failed,
        content: FavoriteContent(
            kind: FavoriteKind.note,
            blocks: [FavoriteBlock(id: 'b1', type: 'text', text: '周五开会')]));
    final repository = _Repository(initial: [failed]);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(FavoriteDetailPage(
        repository: repository,
        item: failed,
        onSend: (_) async =>
            const FavoriteSendResult(status: FavoriteSendStatus.success))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('favorite-detail-send')))
            .onPressed,
        isNull);
    await tester
        .tap(find.byKey(const ValueKey('favorite-detail-retry-archive')));
    await tester.pumpAndSettle();
    expect(repository.archives, 1);
    expect(find.byKey(const ValueKey('favorite-detail-retry-archive')),
        findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('favorite-detail-send')))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'mixed note renders its ordered blocks and keeps rich content out of text-only editing',
      (tester) async {
    const mixed = FavoriteItem(
        id: 'mixed',
        kind: FavoriteKind.note,
        title: '行程',
        version: 1,
        status: FavoriteStatus.ready,
        content: FavoriteContent(kind: FavoriteKind.note, blocks: [
          FavoriteBlock(id: 'first', type: 'text', text: '先到这里'),
          FavoriteBlock(id: 'place', type: 'location', data: {'title': '北京'}),
          FavoriteBlock(id: 'bundle', type: 'message', data: {
            'blocks': [
              {'id': 'nested', 'type': 'text', 'text': '聊天摘录'}
            ]
          }),
        ]));
    final repository = _Repository(initial: [mixed]);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
        _host(FavoriteDetailPage(repository: repository, item: mixed)));
    await tester.pumpAndSettle();
    expect(find.text('先到这里'), findsOneWidget);
    expect(find.text('北京'), findsOneWidget);
    expect(find.text('聊天摘录'), findsOneWidget);
    expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('favorite-block-first')))
            .dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('favorite-block-place')))
            .dy));
    expect(find.byKey(const ValueKey('favorite-detail-edit')), findsNothing);
  });

  testWidgets(
      'narrow picker with long destination and large text keeps usable list bounds',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Repository(initial: [_audioItem]);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(
        _launcher(
            repository,
            (_) async =>
                const FavoriteSendResult(status: FavoriteSendStatus.success),
            target: const FavoriteTarget(
                conversationID: 'c_a',
                userID: 'a',
                displayName: '项目交流与产品设计讨论群，包含多个协作者')),
        scale: 1.5));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const ValueKey('favorites-list'))).height,
        greaterThan(48));
    expect(find.text('7″'), findsOneWidget);
    final voiceThumbnail = find.byType(FavoriteItemThumbnail);
    final audioSize = tester.getSize(voiceThumbnail);
    expect(audioSize.width, greaterThan(audioSize.height * 2));
    expect(tester.getBottomRight(voiceThumbnail).dx, lessThan(320));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('favorite-send-voice_1')))
            .width,
        greaterThanOrEqualTo(40));
  });

  testWidgets('account invalidation immediately hides the open picker content',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(_launcher(
        repository,
        (_) async =>
            const FavoriteSendResult(status: FavoriteSendStatus.success))));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    repository.active = false;
    repository.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorite-favorite_1')), findsNothing);
    expect(find.textContaining('登录状态已改变'), findsOneWidget);
  });

  testWidgets(
      'obsolete batch refreshes and clears selection while detail loads the latest content',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    const obsolete = FavoriteSendResult(
        status: FavoriteSendStatus.failed,
        errorCode: 'BATCH_RESELECT_REQUIRED',
        errorMessage: '内容已更新，请重新选择发送目标');
    var sends = 0;
    await tester.pumpWidget(_host(FavoritesPage(
        repository: repository,
        onSendItemsToConversation: (_) async {
          sends++;
          return obsolete;
        })));
    await tester.pumpAndSettle();
    final initial = repository.requests.length;
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorite-favorite_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorites-send-selected')));
    await tester.pumpAndSettle();
    expect(repository.requests.length, initial + 1);
    expect(find.byKey(const ValueKey('favorites-send-selected')), findsNothing);
    expect(find.text('内容已更新，请重新选择发送目标'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorite-favorite_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorites-send-selected')));
    await tester.pumpAndSettle();
    expect(sends, 2);

    await tester.pumpWidget(_host(FavoriteDetailPage(
        repository: repository, item: _item, onSend: (_) async => obsolete)));
    await tester.pumpAndSettle();
    final loaded = repository.details;
    await tester.tap(find.byKey(const ValueKey('favorite-detail-send')));
    await tester.pumpAndSettle();
    expect(repository.details, loaded + 1);
    expect(find.text('内容已更新，请重新选择发送目标'), findsOneWidget);
  });

  testWidgets(
      'cancel remaining sends requires the warning confirmation and clears the batch selection',
      (tester) async {
    final repository = _Repository();
    addTearDown(repository.dispose);
    final cancelled = <List<String>>[];
    await tester.pumpWidget(_host(FavoritesPage(
        repository: repository,
        onSendItemsToConversation: (_) async => const FavoriteSendResult(
            status: FavoriteSendStatus.unknown, sentCount: 1, totalCount: 2),
        onCancelSendItemsToConversation: (items) async {
          cancelled.add(items.map((item) => item.id).toList());
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorite-favorite_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorites-send-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-cancel-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('取消不会撤回已发消息'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消'));
    await tester.pumpAndSettle();
    expect(cancelled, isEmpty);
    expect(
        find.byKey(const ValueKey('favorites-send-selected')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorites-cancel-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消剩余发送'));
    await tester.pumpAndSettle();
    expect(cancelled, [
      ['favorite_1']
    ]);
    expect(find.byKey(const ValueKey('favorites-cancel-send')), findsNothing);
    expect(find.byKey(const ValueKey('favorites-send-selected')), findsNothing);
  });
}

final _exportPreview =
    Platform.environment['EXPORT_FAVORITE_PICKER_PREVIEW'] == '1';

Future<void> _loadPreviewFonts() async {
  final chinese = File('C:/Windows/Fonts/msyh.ttc');
  if (await chinese.exists()) {
    final bytes = ByteData.sublistView(await chinese.readAsBytes());
    await (FontLoader('FavoritePickerPreviewFont')
          ..addFont(Future.value(bytes)))
        .load();
  }
  final icons = File(
      'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final bytes = await icons.exists()
      ? ByteData.sublistView(await icons.readAsBytes())
      : await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')..addFont(Future.value(bytes))).load();
}

Future<void> _export(
    WidgetTester tester, GlobalKey key, String themeName) async {
  // Asset decoding runs outside the test clock; wait for it before capturing
  // so the first empty-state screenshot includes its illustration too.
  final images = find.byType(Image);
  if (images.evaluate().isNotEmpty) {
    await tester.runAsync(() async {
      for (final element in images.evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pumpAndSettle();
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(
          'build/favorites-preview/favorites-smooth-category-$themeName.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
