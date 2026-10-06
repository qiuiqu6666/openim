import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_cover_page.dart';
import 'package:openim/pages/moments/moments_detail_page.dart';
import 'package:openim/pages/moments/moments_settings_page.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 4; ++i) {
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> _refresh(WidgetTester tester) async {
  unawaited(tester
      .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first)
      .show());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _flush(tester);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 180,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });

  testWidgets('slow cover metadata does not block feed pagination',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    final gate = Completer<MomentsSettings>();
    fixture.api.settingsWork = () => gate.future;
    fixture.api.feedWork = (cursor) async => cursor == null
        ? MomentsPageResult(
            items: [fixture.api.posts[momentsUiFriendPostId]!],
            hasMore: true,
            nextCursor: 'next')
        : MomentsPageResult(items: [fixture.api.posts[momentsUiOwnPostId]!]);
    await mountMomentsUi(tester, fixture: fixture, settle: false);
    await _flush(tester);
    expect(fixture.repository.feedState.items.length, 1);
    expect(fixture.api.settingsRequests, 1);
    expect(find.text('加载更多'), findsOneWidget);
    await tester.ensureVisible(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await _flush(tester);
    expect(fixture.api.feedCursors, [null, 'next']);
    expect(fixture.repository.feedState.items.length, 2);
    gate.complete(const MomentsSettings());
    await tester.pumpAndSettle();
    await _close(tester);
  });

  testWidgets('late cover response does not start a request for a new account',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    final gate = Completer<MomentsSettings>();
    fixture.api.settingsWork = () => gate.future;
    await mountMomentsUi(tester, fixture: fixture, settle: false);
    await _flush(tester);
    expect(fixture.api.settingsRequests, 1);
    fixture.ownerUserId = 'preview-next-owner';
    await fixture.repository.loadPrivacySelections();
    await _flush(tester);
    gate.complete(const MomentsSettings());
    await tester.pumpAndSettle();
    expect(find.text('登录状态已变化'), findsOneWidget);
    expect(fixture.api.notificationRequests, 0);
    await _close(tester);
  });

  testWidgets('initial personal range resolves before album rows are revealed',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    final gate = Completer<MomentsSettings>();
    fixture.api.settingsWork = () => gate.future;
    await mountMomentsUi(tester,
        fixture: fixture, surface: MomentsUiSurface.profile, settle: false);
    await _flush(tester);
    expect(fixture.api.albumRequests, isEmpty);
    expect(find.byKey(const ValueKey('moments_album_post_preview-own-post')),
        findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    gate.complete(const MomentsSettings(visibleRangeDays: 90));
    await tester.pumpAndSettle();
    expect(fixture.api.settingsRequests, 1);
    expect(fixture.api.albumRequests, [momentsUiSelf.userId]);
    expect(find.text('朋友仅能查看最近90天的朋友圈'), findsOneWidget);
    final row =
        find.byKey(const ValueKey('moments_album_post_preview-own-post'));
    final top = tester.getTopLeft(row).dy;
    await _flush(tester);
    expect(tester.getTopLeft(row).dy, top);
    await _close(tester);
  });

  testWidgets('canceling cover editing preserves the paginated feed',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    fixture.api.feedWork = (cursor) async => cursor == null
        ? MomentsPageResult(
            items: [fixture.api.posts[momentsUiFriendPostId]!],
            hasMore: true,
            nextCursor: 'next')
        : MomentsPageResult(items: [fixture.api.posts[momentsUiOwnPostId]!]);
    await mountMomentsUi(tester, fixture: fixture);
    await fixture.repository.loadFeed(refresh: false);
    await tester.pumpAndSettle();
    final cover = find.byKey(const ValueKey('moments_cover'));
    await tester.tapAt(tester.getTopLeft(cover) + const Offset(180, 130));
    await tester.pumpAndSettle();
    expect(find.byType(MomentsCoverPage), findsOneWidget);
    await tester.tap(find.byTooltip('返回').last);
    await tester.pumpAndSettle();
    expect(fixture.api.feedCursors, [null, 'next']);
    expect(fixture.repository.feedState.items.length, 2);
    await _close(tester);
  });

  testWidgets('unchanged settings return preserves the personal album',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    fixture.api.settingsWork =
        () async => const MomentsSettings(visibleRangeDays: 90);
    await mountMomentsUi(tester,
        fixture: fixture, surface: MomentsUiSurface.profile);
    await _reveal(tester, find.text('前往设置'));
    await tester.tap(find.text('前往设置'));
    await tester.pumpAndSettle();
    expect(find.byType(MomentsSettingsPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(MomentsSettingsPage))).pop();
    await tester.pumpAndSettle();
    expect(fixture.api.albumRequests, [momentsUiSelf.userId]);
    expect(fixture.repository.userState(momentsUiSelf.userId).items.length, 3);
    await _close(tester);
  });

  testWidgets('detail refresh keeps the loaded content and scroll position',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    fixture.api.commentItems[momentsUiFriendPostId] = List.generate(
        18,
        (index) => MomentComment(
            commentId: 'long-comment-$index',
            author: momentsUiFriend,
            text: '评论内容 $index',
            createdAt: 1791000600000));
    await mountMomentsUi(tester,
        fixture: fixture, surface: MomentsUiSurface.detail);
    final scroll =
        tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    scroll.controller!.jumpTo(260);
    await tester.pumpAndSettle();
    final offset = scroll.controller!.offset;
    final gate = Completer<MomentPost>();
    fixture.api.detailWork = (_) => gate.future;
    await _refresh(tester);
    expect(fixture.api.detailRequests,
        [momentsUiFriendPostId, momentsUiFriendPostId]);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(scroll.controller!.hasClients, isTrue);
    expect(scroll.controller!.offset, offset);
    gate.complete(fixture.api.posts[momentsUiFriendPostId]!);
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, offset);
    await _close(tester);
  });

  testWidgets('detail initialization and refresh join the same pending load',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    final gate = Completer<MomentsPageResult<MomentComment>>();
    fixture.api.commentsWork = (_, __) => gate.future;
    await mountMomentsUi(tester,
        fixture: fixture, surface: MomentsUiSurface.detail, settle: false);
    await _flush(tester);
    expect(fixture.api.detailRequests, [momentsUiFriendPostId]);
    await _refresh(tester);
    expect(fixture.api.detailRequests, [momentsUiFriendPostId]);
    expect(fixture.api.commentRequests, [null]);
    gate.complete(const MomentsPageResult(items: momentsUiComments));
    await tester.pumpAndSettle();
    await _close(tester);
  });

  testWidgets('failed detail refresh keeps the current content and geometry',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    await mountMomentsUi(tester,
        fixture: fixture, surface: MomentsUiSurface.detail);
    final post = find.byKey(const ValueKey('moments_post_preview-friend-post'));
    final rect = tester.getRect(post);
    fixture.api.detailWork = (_) async => throw StateError('Offline');
    await _refresh(tester);
    await tester.pumpAndSettle();
    expect(tester.getRect(post), rect);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(fixture.api.detailRequests.length, 2);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('pull refresh supersedes a pending feed continuation',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    final gate = Completer<MomentsPageResult<MomentPost>>();
    var homeRequests = 0;
    final original = fixture.api.posts[momentsUiFriendPostId]!;
    final updated = MomentPost.fromJson(
        {...original.toJson(), 'version': 2, 'text': '最新首页内容'});
    fixture.api.feedWork = (cursor) async {
      if (cursor != null) return gate.future;
      ++homeRequests;
      return MomentsPageResult(
          items: [homeRequests == 1 ? original : updated],
          hasMore: homeRequests == 1,
          nextCursor: homeRequests == 1 ? 'next' : null);
    };
    await mountMomentsUi(tester, fixture: fixture);
    await tester.ensureVisible(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await _flush(tester);
    await _refresh(tester);
    expect(fixture.api.feedCursors, [null, 'next', null]);
    expect(fixture.repository.feedState.items.single.text, updated.text);
    gate.complete(MomentsPageResult(
        items: [fixture.api.posts[momentsUiOwnPostId]!],
        hasMore: true,
        nextCursor: 'old-next'));
    await tester.pumpAndSettle();
    expect(fixture.repository.feedState.items.single.text, updated.text);
    expect(fixture.repository.feedState.nextCursor, isNull);
    await _close(tester);
  });

  testWidgets('closing a pending detail load does not register late sync work',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    final gate = Completer<MomentPost>();
    fixture.api.detailWork = (_) => gate.future;
    await mountMomentsUi(tester,
        fixture: fixture, surface: MomentsUiSurface.detail, settle: false);
    await _flush(tester);
    expect(fixture.api.detailRequests, [momentsUiFriendPostId]);
    await _close(tester);
    gate.complete(fixture.api.posts[momentsUiFriendPostId]!);
    await _flush(tester);
    fixture.api.detailWork = null;
    await fixture.repository.refreshAuthorization();
    expect(fixture.api.detailRequests, [momentsUiFriendPostId]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing one of two detail routes retains the other sync lease',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    await mountMomentsUi(tester,
        fixture: fixture, surface: MomentsUiSurface.detail);
    final navigator =
        Navigator.of(tester.element(find.byType(MomentsDetailPage)));
    unawaited(navigator.push<void>(MaterialPageRoute(
        builder: (_) => MomentsDetailPage(
            repository: fixture.repository, momentId: momentsUiFriendPostId))));
    await tester.pumpAndSettle();
    expect(fixture.api.detailRequests.length, 2);
    navigator.pop();
    await tester.pumpAndSettle();
    await fixture.repository.refreshAuthorization();
    await tester.pumpAndSettle();
    expect(fixture.api.detailRequests.length, 3);
    expect(find.byType(MomentsDetailPage), findsOneWidget);
    await _close(tester);
    await fixture.repository.refreshAuthorization();
    expect(fixture.api.detailRequests.length, 3);
    expect(tester.takeException(), isNull);
  });
}
