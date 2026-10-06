import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_actions.dart';
import 'package:openim/pages/moments/moments_media_preview.dart';
import 'package:openim/pages/moments/moments_widgets.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

const _me = MomentUser(userId: 'me', nickname: 'Me');
const _photo = MomentMedia(
    mediaId: 'photo',
    contentPath: '/moments/media/photo/content',
    thumbPath: '/moments/media/photo/content?variant=thumb');
const _post = MomentPost(
    momentId: 'm1',
    author: _me,
    mediaList: [_photo],
    createdAt: 1790985600000,
    canDelete: true,
    canComment: true,
    version: 1);
const _comment = MomentComment(
    commentId: 'c1', author: _me, text: 'Comment', canDelete: true);

// Real image decoding is exercised without files, HTTP, or platform media APIs.
Uint8List _png() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/q8AAAAASUVORK5CYII=');

class _Api extends MomentsApi {
  bool reportsEnabled = true;
  final List<String> deleted = [];
  final List<String> reported = [];
  final List<bool> thumbnails = [];
  Future<Uint8List> Function(int call, bool thumbnail)? mediaWork;

  @override
  Future<MomentsCapabilities> capabilities() async => MomentsCapabilities(
      enabled: true,
      readEnabled: true,
      publishEnabled: true,
      settingsEnabled: true,
      interactionsEnabled: true,
      reportsEnabled: reportsEnabled);

  @override
  Future<void> deletePost(String id) async => deleted.add(id);

  @override
  Future<void> reportPost(String id,
      {required String reason, String? commentId}) async {
    reported.add('$id:$reason');
  }

  @override
  Future<MomentsSettings> setBlockedViewer(String id, bool blocked) async =>
      const MomentsSettings();

  @override
  Future<Uint8List> downloadMedia(MomentMedia media,
      {bool thumbnail = false}) async {
    thumbnails.add(thumbnail);
    return mediaWork?.call(thumbnails.length, thumbnail) ?? _png();
  }
}

class _Session {
  _Session(this.api) {
    repository = MomentsRepository(
        api: api,
        userIdProvider: () => owner,
        environmentProvider: () => environment,
        friendLoader: () async => const [],
        privacySelectionStore: MomentsPrivacySelectionStore(
            readSnapshot: (key) async => _privacySnapshots[key],
            writeSnapshot: (key, value) async {
              _privacySnapshots[key] = value;
              return true;
            }),
        subscribeToSdk: false);
  }
  final _Api api;
  final Map<String, String> _privacySnapshots = {};
  late final MomentsRepository repository;
  String owner = 'me';
  String environment = 'server-a';

  void change(String kind, {bool notify = false}) {
    if (kind == 'account') {
      owner = 'other';
    } else {
      environment = 'server-b';
    }
    if (notify) repository.resetSession();
  }
}

Widget _host(Widget child, {String language = 'en'}) => ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) {
      Styles.isDark = false;
      return MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          home: child);
    });

Widget _actionHost(MomentsRepository repository) => _host(Scaffold(
    body: Builder(
        builder: (context) => Column(children: [
              TextButton(
                  onPressed: () =>
                      unawaited(deleteMoment(context, repository, _post)),
                  child: const Text('Open delete')),
              TextButton(
                  onPressed: () => unawaited(
                      reportMoment(context, repository, _post.momentId)),
                  child: const Text('Open report')),
              TextButton(
                  onPressed: () => unawaited(showMomentCommentActions(
                      context, repository, _post, _comment)),
                  child: const Text('Open comment actions')),
            ]))));

Widget _thumbnailHost(MomentsRepository repository) => _host(Scaffold(
    body: Center(
        child: SizedBox.square(
            dimension: 100,
            child: MomentsMediaImage(repository: repository, media: _photo)))));

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('same-session delete and report reach the API after selection',
      (tester) async {
    final api = _Api();
    final session = _Session(api);
    addTearDown(session.repository.dispose);
    await session.repository.ensureCapabilities();
    await tester.pumpWidget(_actionHost(session.repository));
    await tester.tap(find.text('Open delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Delete'));
    await tester.pumpAndSettle();
    expect(api.deleted, ['m1']);
    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    expect(api.reported, ['m1:SPAM']);
  });

  testWidgets(
      'disabled reports open no report sheet and leave comment actions available',
      (tester) async {
    final api = _Api()..reportsEnabled = false;
    final session = _Session(api);
    addTearDown(session.repository.dispose);
    await session.repository.ensureCapabilities();
    await tester.pumpWidget(_actionHost(session.repository));
    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();
    expect(find.text('Report reason'), findsNothing);
    expect(find.text('Spam'), findsNothing);
    expect(api.reported, isEmpty);
    await tester.tap(find.text('Open comment actions'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Delete comment'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
  });

  for (final language in ['en', 'zh']) {
    testWidgets('backend semantic errors remain distinct in $language',
        (tester) async {
      const codes = [
        'RELATION_UNAVAILABLE',
        'CONTEXT_CHANGED',
        'CURSOR_EXPIRED',
        'MEDIA_NOT_READY',
        'MEDIA_EXPIRED',
        'IDEMPOTENCY_CONFLICT'
      ];
      await tester.pumpWidget(_host(
          Scaffold(
              body: Builder(
            builder: (context) => ListView(children: [
              for (final code in codes)
                Text(momentsErrorText(
                    context,
                    MomentsException('Internal backend trace',
                        code: code,
                        permissionDenied: code == 'CONTEXT_CHANGED')))
            ]),
          )),
          language: language));
      await tester.pumpAndSettle();
      final messages = language == 'en'
          ? const [
              'Could not verify friendship or blocked status. Try again shortly.',
              'Friendship or privacy changed. Refresh and try again.',
              'This list has changed. Reload it to continue.',
              'The image is still processing. Try again shortly.',
              'The uploaded image expired. Choose the image again.',
              'The original task has different content. Keep its original content before retrying.'
            ]
          : const [
              '暂时无法确认好友关系或拉黑状态，请稍后重试',
              '好友关系或隐私设置已变化，请刷新后重试',
              '列表已更新，请重新加载后继续',
              '图片尚未处理完成，请稍后重试',
              '上传的图片已过期，请重新选择图片',
              '原任务内容不一致，请保留原任务与原内容后重试'
            ];
      for (final message in messages) {
        expect(find.text(message), findsOneWidget);
      }
      expect(find.textContaining('Internal backend trace'), findsNothing);
    });
  }

  for (final kind in ['account', 'server']) {
    testWidgets('$kind change during deletion confirmation never writes',
        (tester) async {
      final api = _Api();
      final session = _Session(api);
      addTearDown(session.repository.dispose);
      await session.repository.ensureCapabilities();
      await tester.pumpWidget(_actionHost(session.repository));
      await tester.tap(find.text('Open delete'));
      await tester.pumpAndSettle();
      // Do not depend on a SDK reset event: the scope is checked on confirm.
      session.change(kind);
      await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.deleted, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$kind change during report selection never writes',
        (tester) async {
      final api = _Api();
      final session = _Session(api);
      addTearDown(session.repository.dispose);
      await session.repository.ensureCapabilities();
      await tester.pumpWidget(_actionHost(session.repository));
      await tester.tap(find.text('Open report'));
      await tester.pumpAndSettle();
      session.change(kind);
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      expect(api.reported, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('late preview bytes never render after $kind change',
        (tester) async {
      final pending = Completer<Uint8List>();
      final api = _Api()..mediaWork = (_, __) => pending.future;
      final session = _Session(api);
      final repository = session.repository;
      addTearDown(repository.dispose);
      repository.applyPost(_post);
      await tester.pumpWidget(_host(MomentsMediaPreview(
          repository: repository, post: _post, initialIndex: 0)));
      await tester.pump();
      expect(api.thumbnails, [false]);
      session.change(kind, notify: true);
      await tester.pump();
      final bytes = _png();
      pending.complete(bytes);
      await _pumpFrames(tester);
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.text('Content unavailable'), findsOneWidget);
      expect(
          PaintingBinding.instance.imageCache
              .statusForKey(ExtendedMemoryImageProvider(bytes))
              .untracked,
          isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('late thumbnail bytes never render or reload with $kind token',
        (tester) async {
      final pending = Completer<Uint8List>();
      final api = _Api()..mediaWork = (_, __) => pending.future;
      final session = _Session(api);
      final repository = session.repository;
      addTearDown(repository.dispose);
      await tester.pumpWidget(_thumbnailHost(repository));
      await tester.pump();
      expect(api.thumbnails, [true]);
      session.change(kind, notify: true);
      await tester.pump();
      final bytes = _png();
      pending.complete(bytes);
      await _pumpFrames(tester);
      expect(find.byType(Image), findsNothing);
      expect(api.thumbnails, [true]);
      expect(
          PaintingBinding.instance.imageCache
              .statusForKey(MemoryImage(bytes))
              .untracked,
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('preview evicts decoded image when authorization changes',
      (tester) async {
    final bytes = _png();
    final api = _Api()..mediaWork = (_, __) async => bytes;
    final session = _Session(api);
    final repository = session.repository;
    addTearDown(repository.dispose);
    repository.applyPost(_post);
    await tester.pumpWidget(_host(MomentsMediaPreview(
        repository: repository, post: _post, initialIndex: 0)));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsOneWidget);
    final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    expect(browser.sources.single.bytes, same(bytes));
    expect(browser.sources.single.url, isNull);
    expect(browser.sources.single.thumbnail, isEmpty);
    final provider = ExtendedMemoryImageProvider(bytes);
    expect(PaintingBinding.instance.imageCache.statusForKey(provider).tracked,
        isTrue);
    await repository.setBlockedViewer('friend', true);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsNothing);
    expect(find.text('Content unavailable'), findsOneWidget);
    expect(PaintingBinding.instance.imageCache.statusForKey(provider).untracked,
        isTrue);
    expect(api.thumbnails, [false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'upgrading a photo cannot retain its old thumbnail after revocation',
      (tester) async {
    final first = _png();
    final thumbnail = _png();
    final full = _png();
    final pendingUpgrade = Completer<Uint8List>();
    final api = _Api()
      ..mediaWork = (call, _) async => switch (call) {
            1 => first,
            2 => thumbnail,
            _ => pendingUpgrade.future,
          };
    final session = _Session(api);
    final repository = session.repository;
    addTearDown(repository.dispose);
    const secondPhoto = MomentMedia(mediaId: 'photo2');
    const post = MomentPost(
        momentId: 'm1',
        author: _me,
        mediaList: [_photo, secondPhoto],
        createdAt: 1790985600000);
    repository.applyPost(post);
    await tester.pumpWidget(_host(MomentsMediaPreview(
        repository: repository, post: post, initialIndex: 0)));
    await tester.pumpAndSettle();
    expect(api.thumbnails, [false, true]);
    await tester.drag(
        find.byType(ExtendedImageGesturePageView), const Offset(-700, 0));
    await _pumpFrames(tester);
    expect(api.thumbnails, [false, true, false]);
    final thumbnailProvider = ExtendedMemoryImageProvider(thumbnail);
    expect(
        PaintingBinding.instance.imageCache
            .statusForKey(thumbnailProvider)
            .tracked,
        isTrue);
    pendingUpgrade.complete(full);
    await tester.pumpAndSettle();
    final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    expect(browser.sources[1].bytes, same(full));
    await repository.setBlockedViewer('friend', true);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byType(MediaBrowser), findsNothing);
    for (final bytes in [first, thumbnail, full]) {
      expect(
          PaintingBinding.instance.imageCache
              .statusForKey(ExtendedMemoryImageProvider(bytes))
              .untracked,
          isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'thumbnail revocation removes old image and requires explicit retry',
      (tester) async {
    final bytes = _png();
    final api = _Api()..mediaWork = (_, __) async => bytes;
    final session = _Session(api);
    final repository = session.repository;
    addTearDown(repository.dispose);
    await tester.pumpWidget(_thumbnailHost(repository));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    final provider = MemoryImage(bytes);
    expect(PaintingBinding.instance.imageCache.statusForKey(provider).tracked,
        isTrue);
    await repository.setBlockedViewer('friend', true);
    await _pumpFrames(tester);
    expect(find.byType(Image), findsNothing);
    expect(PaintingBinding.instance.imageCache.statusForKey(provider).untracked,
        isTrue);
    expect(api.thumbnails, [true]);
    // A denied retry must neither restore the old bytes nor start a request loop.
    api.mediaWork = (_, __) async =>
        throw const MomentsException('denied', permissionDenied: true);
    await tester.tap(find.byTooltip('Retry image'));
    await _pumpFrames(tester);
    expect(api.thumbnails, [true, true]);
    expect(find.byType(Image), findsNothing);
    expect(PaintingBinding.instance.imageCache.statusForKey(provider).untracked,
        isTrue);
    expect(tester.takeException(), isNull);
  });
}
