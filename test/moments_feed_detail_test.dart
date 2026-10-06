import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_detail_page.dart';
import 'package:openim/pages/moments/moments_page.dart';
import 'package:openim/pages/moments/moments_likes_page.dart';
import 'package:openim/pages/moments/moments_widgets.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

const _friend = MomentUser(userId: 'friend', nickname: 'Friend');
const _stranger = MomentUser(userId: 'stranger', nickname: 'Hidden Person');
const _self = MomentUser(userId: 'me', nickname: 'Me');
bool _previewFontsLoaded = false;
MomentPost _post(String id,
        {bool liked = false, List<MomentComment> comments = const []}) =>
    MomentPost(
        momentId: id,
        author: _friend,
        text: 'A quiet afternoon by the lake. $id',
        createdAt: DateTime(2026, 10, 3, 10).millisecondsSinceEpoch,
        version: 1,
        canLike: true,
        canComment: true,
        likedByMe: liked,
        likesPreview: [if (liked) const MomentLike(user: _self)],
        likeCount: liked ? 1 : 0,
        commentsPreview: comments,
        commentCount: comments.length);

class _Api extends MomentsApi {
  bool enabled = true;
  bool failMore = false;
  bool failDetail = false;
  bool failFeedRefresh = false;
  bool unknownComment = false;
  bool failCommentQuery = false;
  final List<String?> cursors = [];
  final List<String> commentKeys = [];
  final List<String> commentBodies = [];
  final List<bool> likeWrites = [];
  final List<String?> likeCursors = [];
  bool failLikesMore = false;
  final Map<String, MomentPost> posts = {'m1': _post('m1'), 'm2': _post('m2')};
  final List<MomentComment> commentsList = [];
  bool paginated = false;
  @override
  Future<MomentsCapabilities> capabilities() async => MomentsCapabilities(
      enabled: enabled,
      readEnabled: enabled,
      publishEnabled: enabled,
      settingsEnabled: enabled,
      interactionsEnabled: enabled);
  @override
  Future<MomentsPageResult<MomentPost>> feed(
      {String? cursor, int pageSize = 20}) async {
    cursors.add(cursor);
    if (cursor == null && failFeedRefresh) {
      throw const MomentsException('network');
    }
    if (cursor != null && failMore) throw const MomentsException('network');
    return MomentsPageResult(
        items: [posts[cursor == null ? 'm1' : 'm2']!],
        nextCursor: cursor == null && paginated ? 'cursor1' : null,
        hasMore: cursor == null && paginated);
  }

  @override
  Future<MomentsPageResult<MomentPost>> userMoments(String userId,
          {String? cursor, int pageSize = 20}) async =>
      MomentsPageResult(
          items: [posts['m1']!], author: _friend, visibleRangeDays: 90);
  @override
  Future<MomentPost> detail(String id) async {
    if (failDetail) {
      throw const MomentsException('denied', permissionDenied: true);
    }
    return posts[id]!;
  }

  @override
  Future<MomentsPageResult<MomentComment>> comments(String id,
          {String? cursor, int pageSize = 20}) async =>
      MomentsPageResult(items: List.of(commentsList));
  @override
  Future<void> setLiked(String id, bool liked) async {
    likeWrites.add(liked);
    posts[id] = _post(id, liked: liked, comments: commentsList);
  }

  @override
  Future<MomentsPageResult<MomentLike>> likes(String id,
      {String? cursor, int pageSize = 20}) async {
    likeCursors.add(cursor);
    if (cursor != null && failLikesMore) {
      throw const MomentsException('network');
    }
    return MomentsPageResult(
        items: cursor == null
            ? const [MomentLike(user: _friend), MomentLike(user: _stranger)]
            : const [MomentLike(user: _self)],
        nextCursor: cursor == null ? 'likes2' : null,
        hasMore: cursor == null);
  }

  @override
  Future<MomentComment> createComment(String id,
      {required String text,
      required String clientRequestId,
      String? replyToCommentId}) async {
    commentKeys.add(clientRequestId);
    commentBodies.add(text);
    if (unknownComment) {
      throw const MomentsException('unknown', unknownResult: true);
    }
    final comment = MomentComment(
        commentId: 'new-comment',
        author: _self,
        text: text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        canDelete: true);
    commentsList.add(comment);
    posts[id] = _post(id, comments: commentsList);
    return comment;
  }

  @override
  Future<MomentsWriteResult> queryCommentResult(String id) async {
    if (failCommentQuery) throw const MomentsException('query network failed');
    return const MomentsWriteResult(status: 'NOT_FOUND');
  }

  @override
  Future<MomentsSettings> settings() async => const MomentsSettings();
  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
          {String? cursor, int pageSize = 20}) async =>
      const MomentsPageResult(items: [
        MomentNotification(
            notificationId: 'n1', actor: _friend, type: 'LIKE', momentId: 'm1')
      ], unreadCount: 1);
}

MomentsRepository _repo(_Api api, {String Function()? userIdProvider}) =>
    MomentsRepository(
        api: api,
        userIdProvider: userIdProvider ?? () => 'me',
        environmentProvider: () => 'test',
        friendLoader: () async => [_friend],
        subscribeToSdk: false);

Widget _host(Widget child,
        {bool dark = false,
        String language = 'en',
        double textScale = 1,
        GlobalKey? previewKey}) =>
    ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) {
          Styles.isDark = dark;
          return MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('zh')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              theme: (dark ? ThemeData.dark() : ThemeData.light()).copyWith(
                  textTheme: (dark ? ThemeData.dark() : ThemeData.light())
                      .textTheme
                      .apply(
                          fontFamily: _previewFontsLoaded
                              ? 'MomentsPreviewFont'
                              : null)),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!),
              home: previewKey == null
                  ? child
                  : RepaintBoundary(key: previewKey, child: child));
        });

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    // Every test uses a mobile viewport, including error states below the cover.
    view.physicalSize = const Size(375, 812);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });
  testWidgets('unavailable feed can retry once backend opens', (tester) async {
    final api = _Api()..enabled = false;
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester
        .pumpWidget(_host(MomentsPage(repository: repo, profileUser: _self)));
    await tester.pumpAndSettle();
    expect(find.text('Moments is coming soon'), findsOneWidget);
    expect(api.cursors, isEmpty);
    api.enabled = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('A quiet afternoon by the lake. m1'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // Viewer-scoped unread activity.
  });

  testWidgets(
      'feed and detail menus hide reports while declared post actions remain',
      (tester) async {
    final api = _Api();
    api.posts['m1'] = const MomentPost(
        momentId: 'm1', author: _self, text: 'Own post', canDelete: true);
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester.pumpWidget(_host(MomentsPage(repository: repo)));
    await tester.pumpAndSettle();
    final postMore = find.descendant(
        of: find.ancestor(
            of: find.text('Own post'), matching: find.byType(MomentsPostCard)),
        matching: find.byTooltip('More'));
    expect(postMore, findsOneWidget);
    await tester.ensureVisible(postMore);
    await tester.tap(postMore);
    await tester.pumpAndSettle();
    expect(find.text('View details'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(postMore, findsOneWidget);
    await tester.tap(postMore);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
  });

  testWidgets('foreign interactions and their raw totals never render',
      (tester) async {
    final api = _Api();
    api.posts['m1'] = MomentPost(
        momentId: 'm1',
        author: _self,
        text: 'Visible post',
        likesPreview: const [
          MomentLike(user: _friend),
          MomentLike(user: _stranger)
        ],
        likeCount: 777,
        commentsPreview: const [
          MomentComment(
              commentId: 'c1', author: _stranger, text: 'Secret text'),
          MomentComment(
              commentId: 'c2', author: _friend, text: 'Friendly comment'),
          MomentComment(
              commentId: 'c3',
              author: _self,
              text: 'Secret reply',
              replyToCommentId: 'c1',
              replyToUser: _stranger)
        ],
        commentCount: 888,
        canLike: true,
        canComment: true);
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester.pumpWidget(_host(MomentsPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.textContaining('Friendly comment', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Secret', findRichText: true), findsNothing);
    expect(find.text('Hidden Person'), findsNothing);
    expect(find.text('777'), findsNothing);
    expect(find.text('888'), findsNothing);
  });

  testWidgets(
      'paging failure retains cursor and retries without duplicate posts',
      (tester) async {
    final api = _Api()
      ..paginated = true
      ..failMore = true;
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester.pumpWidget(_host(MomentsPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    api.failMore = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.cursors, [null, 'cursor1', 'cursor1']);
    expect(repo.feedState.items.map((post) => post.momentId), ['m1', 'm2']);
  });

  testWidgets(
      'detail writes update shared feed and comments appear immediately',
      (tester) async {
    final api = _Api();
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await repo.loadFeed();
    await tester
        .pumpWidget(_host(MomentsDetailPage(repository: repo, momentId: 'm1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Like'));
    await tester.pumpAndSettle();
    expect(repo.feedState.items.single.likedByMe, isTrue);
    expect(api.likeWrites, [true]);
    await tester.tap(find.text('Write a comment…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A new visible comment');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A new visible comment', findRichText: true),
        findsOneWidget);
    expect(api.commentKeys.single, isNotEmpty);
  });

  testWidgets('refresh failure with exhausted feed retries the refresh request',
      (tester) async {
    final api = _Api();
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester.pumpWidget(_host(MomentsPage(repository: repo)));
    await tester.pumpAndSettle();
    api.failFeedRefresh = true;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    api.failFeedRefresh = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.cursors, [null, null, null]);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets(
      'deleted reply target renders anonymously and never shows user ID',
      (tester) async {
    final api = _Api();
    api.commentsList.add(const MomentComment(
        commentId: 'deleted-reply',
        author: _self,
        text: 'A lawful reply',
        replyTargetDeleted: true,
        replyToCommentId: 'deleted',
        replyToUser: MomentUser(userId: 'friend')));
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester
        .pumpWidget(_host(MomentsDetailPage(repository: repo, momentId: 'm1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Deleted comment', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('friend：', findRichText: true), findsNothing);
  });

  testWidgets('unknown comment freezes payload and reuses the same request',
      (tester) async {
    final api = _Api()..unknownComment = true;
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester
        .pumpWidget(_host(MomentsDetailPage(repository: repo, momentId: 'm1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write a comment…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep this payload');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    api.unknownComment = false;
    await tester.tap(find.text('Confirm and retry'));
    await tester.pumpAndSettle();
    expect(api.commentKeys.toSet().length, 1);
    expect(api.commentBodies, ['Keep this payload', 'Keep this payload']);
  });

  testWidgets(
      'account changes clear an open comment and prevent its submission',
      (tester) async {
    var user = 'me';
    final api = _Api();
    final repo = _repo(api, userIdProvider: () => user);
    addTearDown(repo.dispose);
    await tester
        .pumpWidget(_host(MomentsDetailPage(repository: repo, momentId: 'm1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write a comment…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Private draft');
    await tester.pump();
    user = 'another-account';
    repo.resetSession();
    await tester.pumpAndSettle();
    expect(find.text('Private draft'), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Account changed'), findsOneWidget);
    expect(api.commentKeys, isEmpty);
  });

  testWidgets('unknown comment stays frozen when confirmation query fails',
      (tester) async {
    final api = _Api()
      ..unknownComment = true
      ..failCommentQuery = true;
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester
        .pumpWidget(_host(MomentsDetailPage(repository: repo, momentId: 'm1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write a comment…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Do not duplicate');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm and retry'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(api.commentKeys.length, 1);
  });

  testWidgets('detail authorization failure clears its cached post',
      (tester) async {
    final api = _Api();
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await repo.loadFeed();
    api.failDetail = true;
    await tester
        .pumpWidget(_host(MomentsDetailPage(repository: repo, momentId: 'm1')));
    await tester.pumpAndSettle();
    expect(find.text('Post unavailable'), findsOneWidget);
    expect(find.text('A quiet afternoon by the lake. m1'), findsNothing);
    expect(repo.postsById, isEmpty);
  });

  testWidgets('friend timeline uses server profile and visible history range',
      (tester) async {
    final repo = _repo(_Api());
    addTearDown(repo.dispose);
    await tester
        .pumpWidget(_host(MomentsPage(repository: repo, authorId: 'friend')));
    await tester.pumpAndSettle();
    final avatar = tester.widget<AvatarView>(
        find.byKey(const ValueKey('moments_header_avatar')));
    expect(avatar.text, 'Friend');
    expect(find.byTooltip('Friend'), findsOneWidget);
    expect(find.text('Posts from the past 90 days'), findsOneWidget);
    expect(find.byTooltip('Create post'), findsNothing);
  });

  testWidgets('likes list filters foreign actors and preserves cursor on retry',
      (tester) async {
    final api = _Api()..failLikesMore = true;
    final repo = _repo(api);
    addTearDown(repo.dispose);
    await tester
        .pumpWidget(_host(MomentsLikesPage(repository: repo, momentId: 'm1')));
    await tester.pumpAndSettle();
    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('Hidden Person'), findsNothing);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Likes unavailable'), findsOneWidget);
    api.failLikesMore = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Friend'), findsOneWidget);
    expect(api.likeCursors, [null, 'likes2', 'likes2']);
  });

  testWidgets('open likes list clears visible identities when account changes',
      (tester) async {
    var user = 'me';
    final repo = _repo(_Api(), userIdProvider: () => user);
    addTearDown(repo.dispose);
    await tester
        .pumpWidget(_host(MomentsLikesPage(repository: repo, momentId: 'm1')));
    await tester.pumpAndSettle();
    user = 'next-account';
    repo.resetSession();
    await tester.pumpAndSettle();
    expect(find.text('Friend'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'feed fits narrow ${dark ? 'dark' : 'light'} screen with large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _repo(_Api());
      addTearDown(repo.dispose);
      await tester.pumpWidget(_host(
          MomentsPage(repository: repo, profileUser: _self),
          dark: dark,
          textScale: 1.5));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('render review previews using test-only fixture data',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final systemFont = File('C:/Windows/Fonts/msyh.ttc');
      if (await systemFont.exists()) {
        final loader = FontLoader('MomentsPreviewFont')
          ..addFont(systemFont
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        _previewFontsLoaded = true;
      }
    });
    for (final dark in [false, true]) {
      final repo = _repo(_Api());
      final key = GlobalKey();
      await tester.pumpWidget(_host(
          MomentsPage(key: UniqueKey(), repository: repo, profileUser: _self),
          language: 'zh',
          dark: dark,
          previewKey: key));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/moments-preview-${dark ? 'dark' : 'light'}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    }
  });
}
