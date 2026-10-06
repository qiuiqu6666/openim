import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_compose_page.dart';
import 'package:openim/pages/moments/moments_draft_store.dart';
import 'package:openim/pages/moments/moments_visibility_page.dart';
import 'package:openim/services/moments_repository.dart';

class _Api extends MomentsApi {
  _Api() : super(baseUrl: 'https://moments.example');
  bool available = true;
  bool uncertain = false;
  Completer<void>? createGate;
  final requestIds = <String>[];
  @override
  Future<MomentsCapabilities> capabilities() async {
    if (!available) {
      throw const MomentsException('not available', unavailable: true);
    }
    return const MomentsCapabilities(
        enabled: true, readEnabled: true, publishEnabled: true);
  }

  @override
  Future<MomentPost> createPost(
      {required String clientRequestID,
      String text = '',
      List<String> mediaIds = const [],
      String visibility = 'FRIENDS',
      List<String> audienceUserIds = const []}) async {
    requestIds.add(clientRequestID);
    if (createGate != null) await createGate!.future;
    if (uncertain) throw const MomentsException('timeout', unknownResult: true);
    return MomentPost(
        momentId: 'created',
        author: const MomentUser(userId: 'me'),
        text: text,
        version: 1);
  }

  @override
  Future<MomentsWriteResult> queryPublishResult(String clientRequestID) async =>
      const MomentsWriteResult(status: 'NOT_FOUND');
}

Widget _host(Widget page,
        {bool dark = false, String language = 'zh', double scale = 1}) =>
    ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              locale: Locale(language),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => page)),
                          child: const Text('open')))),
            ));
Future<void> _open(WidgetTester tester, Widget page,
    {bool dark = false, String language = 'zh', double scale = 1}) async {
  await tester
      .pumpWidget(_host(page, dark: dark, language: language, scale: scale));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _draftRecord(MomentsDraftStore store,
        {String text = 'Original draft', MomentsPublishJob? job}) =>
    {
      'version': 1,
      'owner': store.ownerUserId,
      'service': store.serviceKey,
      'text': text,
      'visibility': const MomentsVisibilitySelection().toJson(),
      'media': <Map<String, dynamic>>[],
      'job': job?.toJson(),
    };

void main() {
  late _Api api;
  late MomentsRepository repository;
  late MomentsDraftStore store;
  Map<String, dynamic>? saved;
  var owner = 'me';
  var failSave = false;
  Completer<void>? saveGate;
  setUp(() async {
    api = _Api();
    saved = null;
    owner = 'me';
    failSave = false;
    saveGate = null;
    repository = MomentsRepository(
        api: api,
        subscribeToSdk: false,
        userIdProvider: () => owner,
        friendLoader: () async => const [
              MomentUser(userId: 'alice', nickname: 'Alice'),
              MomentUser(userId: 'bob', nickname: 'Bob')
            ]);
    store = MomentsDraftStore(
        repository: repository,
        read: () async => saved,
        write: (value) async {
          if (saveGate != null) await saveGate!.future;
          if (failSave) throw StateError('disk');
          saved = value;
        });
    await store.load();
  });
  tearDown(() {
    store.dispose();
    repository.dispose();
  });

  testWidgets('an unreadable draft can leave without replacing its record',
      (tester) async {
    store.dispose();
    var writes = 0;
    store = MomentsDraftStore(
        repository: repository,
        read: () async => throw const FileSystemException('unreadable'),
        write: (_) async => writes++);
    await store.load();
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store),
        language: 'en');
    expect(find.text('Could not read your draft. Read it again to continue.'),
        findsOneWidget);
    expect(find.text('Retry saving'), findsNothing);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('moments_compose_text')))
            .enabled,
        isFalse);
    await tester.tap(find.byKey(const ValueKey('moments_compose_close')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(writes, 0);
    expect(api.requestIds, isEmpty);
  });

  testWidgets('reading a draft again restores the original text before editing',
      (tester) async {
    store.dispose();
    var readable = false;
    var writes = 0;
    store = MomentsDraftStore(
        repository: repository,
        read: () async {
          if (!readable) throw const FileSystemException('unreadable');
          return _draftRecord(store);
        },
        write: (_) async => writes++);
    await store.load();
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store),
        language: 'en');
    readable = true;
    await tester.tap(find.byKey(const ValueKey('moments_retry_recovery')));
    await tester.pumpAndSettle();
    final field = tester
        .widget<TextField>(find.byKey(const ValueKey('moments_compose_text')));
    expect(field.controller!.text, 'Original draft');
    expect(field.enabled, isTrue);
    expect(find.byKey(const ValueKey('moments_retry_recovery')), findsNothing);
    expect(writes, 0);
    await tester.enterText(
        find.byKey(const ValueKey('moments_compose_text')), 'Finish the draft');
    await tester.pump(const Duration(milliseconds: 400));
    expect(store.text, 'Finish the draft');
    expect(writes, 1);
  });

  testWidgets('retrying a saved unknown task keeps its original publish ID',
      (tester) async {
    store.dispose();
    var readable = false;
    var reads = 0;
    var writes = 0;
    store = MomentsDraftStore(
        repository: repository,
        read: () async {
          reads++;
          if (!readable) throw const FileSystemException('unreadable');
          return _draftRecord(store,
              job: MomentsPublishJob(
                  clientRequestID: 'original-publish-task',
                  text: 'Original draft',
                  visibility: const MomentsVisibilitySelection(),
                  mediaOrder: const [],
                  submitted: true));
        },
        write: (_) async => writes++);
    await store.load();
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store),
        language: 'en');
    await tester.tap(find.byKey(const ValueKey('moments_retry_recovery')));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(store.recoveryFailed, isTrue);
    expect(writes, 0);
    readable = true;
    await tester.tap(find.byKey(const ValueKey('moments_retry_recovery')));
    await tester.pumpAndSettle();
    expect(store.job!.clientRequestID, 'original-publish-task');
    final field = tester
        .widget<TextField>(find.byKey(const ValueKey('moments_compose_text')));
    expect(field.controller!.text, 'Original draft');
    expect(field.enabled, isFalse);
    expect(writes, 0);
    await tester.tap(find.byKey(const ValueKey('moments_publish')));
    await tester.pumpAndSettle();
    expect(api.requestIds, ['original-publish-task']);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
      'a completed publish closes its leave confirmation and the compose route once',
      (tester) async {
    api.createGate = Completer<void>();
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store),
        language: 'en');
    await tester.enterText(
        find.byKey(const ValueKey('moments_compose_text')), 'A moment');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('moments_publish')));
    await tester.pumpAndSettle();
    expect(api.requestIds, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('moments_compose_close')));
    await tester.pumpAndSettle();
    expect(find.text('Leave this post?'), findsOneWidget);
    api.createGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'repeated back while saving a draft cannot open a second dialog or pop twice',
      (tester) async {
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store),
        language: 'en');
    await tester.enterText(
        find.byKey(const ValueKey('moments_compose_text')), 'Keep this draft');
    await tester.tap(find.byKey(const ValueKey('moments_compose_close')));
    await tester.pumpAndSettle();
    saveGate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('moments_save_leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('moments_compose_close')));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('open'), findsNothing);
    saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(saved!['text'], 'Keep this draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unavailable backend keeps editing and saving; publish is disabled',
      (tester) async {
    api.available = false;
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store));
    expect(find.text('朋友圈暂未开放，请稍后再来'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('moments_compose_text')), '留给明天');
    expect(store.text, '留给明天');
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('moments_publish')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('moments_compose_close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('moments_save_leave')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(saved!['text'], '留给明天');
    expect(api.requestIds, isEmpty);
  });
  testWidgets(
      'unknown publish locks editing and retries the original request in English dark mode',
      (tester) async {
    api.uncertain = true;
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store),
        dark: true, language: 'en');
    await tester.enterText(
        find.byKey(const ValueKey('moments_compose_text')), 'hello');
    expect(store.text, 'hello');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('moments_publish')));
    await tester.pumpAndSettle();
    expect(store.resultUncertain, isTrue);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('moments_compose_text')))
            .enabled,
        isFalse);
    await tester.ensureVisible(find.text('Confirming the publish result'));
    await tester.pumpAndSettle();
    expect(find.text('Confirming the publish result'), findsOneWidget);
    api.uncertain = false;
    await tester.tap(find.byKey(const ValueKey('moments_publish')));
    await tester.pumpAndSettle();
    expect(api.requestIds, hasLength(2));
    expect(api.requestIds.first, api.requestIds.last);
    expect(saved, isNull);
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets(
      'composer privacy follows the action sheet and validates restored friends',
      (tester) async {
    await store.updateVisibility(const MomentsVisibilitySelection(
        mode: 'PARTIAL', audienceUserIds: ['alice', 'removed-friend']));
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store));
    await tester
        .ensureVisible(find.byKey(const ValueKey('moments_choose_visibility')));
    await tester.tap(find.byKey(const ValueKey('moments_choose_visibility')));
    await tester.pumpAndSettle();
    expect(find.text('所有好友可见'), findsOneWidget);
    await tester.tap(find.text('部分可见'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('removed-friend'), findsNothing);
    expect(store.visibility.audienceUserIds, ['alice', 'removed-friend']);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('moments_privacy_picker_done')))
            .onPressed,
        isNotNull);
    await tester.tap(find.byKey(const ValueKey('moments_privacy_picker_done')));
    await tester.pumpAndSettle();
    expect(store.visibility.mode, 'PARTIAL');
    expect(store.visibility.audienceUserIds, ['alice']);
    expect(api.requestIds, isEmpty);
  });

  testWidgets('composer can choose only me without opening the friend selector',
      (tester) async {
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store),
        language: 'en');
    await tester
        .ensureVisible(find.byKey(const ValueKey('moments_choose_visibility')));
    await tester.tap(find.byKey(const ValueKey('moments_choose_visibility')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only me'));
    await tester.pumpAndSettle();
    expect(store.visibility.mode, 'SELF');
    expect(store.visibility.audienceUserIds, isEmpty);
    expect(find.byKey(const ValueKey('moments_privacy_friend_search')),
        findsNothing);
    expect(api.requestIds, isEmpty);
  });

  testWidgets(
      'visibility supports SELF and requires a current selected friend for PARTIAL',
      (tester) async {
    await _open(tester, MomentsVisibilityPage(repository: repository));
    await tester.tap(find.byKey(const ValueKey('moments_visibility_SELF')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('moments_visibility_done')))
            .onPressed,
        isNotNull);
    await tester.tap(find.byKey(const ValueKey('moments_visibility_PARTIAL')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('moments_visibility_done')))
            .onPressed,
        isNull);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('moments_friend_alice')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('moments_friend_alice')));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('moments_visibility_done')))
            .onPressed,
        isNotNull);
    await tester.tap(find.byKey(const ValueKey('moments_visibility_done')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets(
      'friend loading errors do not become an empty successful audience',
      (tester) async {
    final broken = MomentsRepository(
        api: api,
        subscribeToSdk: false,
        userIdProvider: () => 'me',
        friendLoader: () async =>
            throw const MomentsException('friends offline'));
    await _open(
        tester,
        MomentsVisibilityPage(
            repository: broken,
            initialSelection: const MomentsVisibilitySelection(
                mode: 'EXCLUDE', audienceUserIds: ['alice'])));
    await tester.scrollUntilVisible(find.text('好友列表加载失败'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('好友列表加载失败'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('moments_visibility_done')))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    broken.dispose();
  });
  testWidgets('account change immediately hides the old friend audience',
      (tester) async {
    await _open(
        tester,
        MomentsVisibilityPage(
            repository: repository,
            initialSelection: const MomentsVisibilitySelection(
                mode: 'PARTIAL', audienceUserIds: ['alice'])));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('moments_friend_alice')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Alice'), findsOneWidget);
    owner = 'other';
    await repository.ensureCapabilities(force: true);
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.byKey(const ValueKey('moments_friend_search')), findsNothing);
    expect(find.text('登录状态已改变'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('moments_visibility_done')))
            .onPressed,
        isNull);
  });
  testWidgets(
      'Unicode code point limit disables submission and reports an inline error',
      (tester) async {
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store));
    await tester.enterText(find.byKey(const ValueKey('moments_compose_text')),
        List.filled(2001, '🌳').join());
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('moments_publish')))
            .onPressed,
        isNull);
    expect(find.text('正文最多 2000 个字'), findsOneWidget);
    expect(api.requestIds, isEmpty);
  });
  testWidgets('save failure keeps the route open and disables publishing',
      (tester) async {
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store));
    failSave = true;
    await tester.enterText(
        find.byKey(const ValueKey('moments_compose_text')), 'do not lose this');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('草稿保存失败，请重试后再发布或离开。'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('moments_publish')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('moments_compose_close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('moments_save_leave')));
    await tester.pumpAndSettle();
    expect(find.byType(MomentsComposePage), findsOneWidget);
    failSave = false;
  });
  testWidgets('account change immediately hides the old private draft',
      (tester) async {
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store));
    await tester.enterText(find.byKey(const ValueKey('moments_compose_text')),
        'private old account');
    await tester.pump(const Duration(milliseconds: 400));
    owner = 'other';
    await repository.ensureCapabilities(force: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('moments_compose_text')), findsNothing);
    expect(find.text('登录状态已改变'), findsOneWidget);
    expect(saved!['owner'], 'me');
  });
  testWidgets(
      'narrow portrait and landscape support large text without overflow',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store),
        dark: true, language: 'en', scale: 1.8);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(812, 375);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _open(tester, MomentsVisibilityPage(repository: repository),
        dark: true, language: 'en', scale: 1.8);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'image option removal preserves remaining order and uses real local files',
      (tester) async {
    final directory = await tester
        .runAsync(() => Directory.systemTemp.createTemp('moments-ui-test-'));
    final imageBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/q8AAAAASUVORK5CYII=');
    final files = await tester.runAsync(() async => [
          await File('${directory!.path}/one.png').writeAsBytes(imageBytes),
          await File('${directory.path}/two.png').writeAsBytes(imageBytes),
        ]);
    store.dispose();
    await tester.runAsync(() async {
      store = MomentsDraftStore(
          repository: repository,
          read: () async => null,
          write: (value) async {
            saved = value;
          },
          directory: () async => Directory('${directory!.path}/drafts'),
          compress: (file) async => file);
      await store.load();
      await store.addFiles(files!);
    });
    final remainingId = store.media.last.clientMediaId;
    await _open(
        tester, MomentsComposePage(repository: repository, draftStore: store));
    await tester
        .ensureVisible(find.byKey(const ValueKey('moments_image_menu_0')));
    await tester.tap(find.byKey(const ValueKey('moments_image_menu_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除图片'));
    await tester.pumpAndSettle();
    expect(store.media, hasLength(1));
    expect(store.media.single.clientMediaId, remainingId);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => directory!.delete(recursive: true));
  });
}
