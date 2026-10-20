import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/presentation/moments_post_card.dart';
import 'package:openim/pages/moments/presentation/moments_cover_header.dart';
import 'package:openim/pages/moments/moments_compose_page.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });
  testWidgets('like and comment update only their row without reloading feed',
      (tester) async {
    final posts = momentsUiPosts()
        .take(2)
        .map((p) => MomentPost.fromJson({
              ...p.toJson(),
              'mediaList': [],
              'commentsPreview': [],
              'likesPreview': [],
            }))
        .toList();
    final fixture = MomentsUiFixture(posts: posts);
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    await mountMomentsUi(tester, fixture: fixture);
    Finder card(String id) => find.byWidgetPredicate(
        (w) => w is MomentsPostCard && w.post.momentId == id);
    final first = card(posts.first.momentId);
    final other = card(posts.last.momentId);
    final headerBefore = tester.widget(find.byType(MomentsCoverHeader));
    final otherBefore = tester.widget(other);
    final otherElement = tester.element(other);
    final headerState = tester.state(find.byType(MomentsCoverHeader));
    final controller = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    final offset = controller.offset;
    final requests = fixture.api.feedCursors.length;
    final before = tester.widget<MomentsPostCard>(first);
    before.onLike();
    await tester.pumpAndSettle();
    expect(tester.widget<MomentsPostCard>(first).post.likedByMe,
        !before.post.likedByMe);
    expect(identical(tester.widget(other), otherBefore), isTrue);
    expect(
        identical(tester.widget(find.byType(MomentsCoverHeader)), headerBefore),
        isTrue);
    expect(controller.offset, offset);
    await fixture.repository
        .addComment(posts.first.momentId, text: 'local update');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MomentsPostCard>(first)
            .post
            .commentsPreview
            .any((c) => c.text == 'local update'),
        isTrue);
    expect(identical(tester.widget(other), otherBefore), isTrue);
    expect(
        identical(tester.widget(find.byType(MomentsCoverHeader)), headerBefore),
        isTrue);
    expect(fixture.api.feedCursors.length, requests);
    expect(controller.offset, offset);
    await fixture.repository.deletePost(posts.first.momentId);
    await tester.pumpAndSettle();
    expect(first, findsNothing);
    expect(other, findsOneWidget);
    expect(identical(tester.element(other), otherElement), isTrue);
    expect(
        identical(tester.state(find.byType(MomentsCoverHeader)), headerState),
        isTrue);
    expect(fixture.api.feedCursors.length, requests);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('confirmed publish returns without reloading or remounting rows',
      (tester) async {
    final posts = momentsUiPosts()
        .take(2)
        .map((post) => MomentPost.fromJson({...post.toJson(), 'mediaList': []}))
        .toList();
    final fixture = MomentsUiFixture(posts: posts);
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    await mountMomentsUi(tester, fixture: fixture);
    await fixture.repository.loadUser(momentsUiSelf.userId);
    await fixture.repository.loadUser(momentsUiFriend.userId);
    final friendItems =
        fixture.repository.userState(momentsUiFriend.userId).items;
    fixture.repository.feedState.nextCursor = 'retained-next-page';
    final ownState = fixture.repository.userState(momentsUiSelf.userId);
    ownState.nextCursor = 'retained-album-page';
    await tester.pumpAndSettle();
    Finder card(String id) => find.byWidgetPredicate(
        (w) => w is MomentsPostCard && w.post.momentId == id);
    final retained = tester.element(card(posts.first.momentId));
    final requests = fixture.api.feedCursors.length;
    final controller = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    final offset = controller.offset;
    tester
        .widget<MomentsCoverHeader>(find.byType(MomentsCoverHeader))
        .onCompose!();
    await tester.pumpAndSettle();
    final published = MomentPost(
        momentId: 'confirmed-new-post',
        author: momentsUiSelf,
        text: 'New post',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        version: 1);
    // The publish worker completes before its route returns the server result.
    fixture.repository.applyPublishedPost(published);
    Navigator.of(tester.element(find.byType(MomentsComposePage)))
        .pop(published);
    await tester.pumpAndSettle();
    expect(card(published.momentId), findsOneWidget);
    expect(identical(tester.element(card(posts.first.momentId)), retained),
        isTrue);
    expect(fixture.api.feedCursors.length, requests);
    expect(controller.offset, offset);
    fixture.repository.applyPublishedPost(published);
    await tester.pumpAndSettle();
    expect(
        fixture.repository.feedState.items
            .where((p) => p.momentId == published.momentId),
        hasLength(1));
    expect(ownState.items.first.momentId, published.momentId);
    expect(ownState.nextCursor, 'retained-album-page');
    expect(fixture.repository.feedState.nextCursor, 'retained-next-page');
    expect(
        identical(fixture.repository.userState(momentsUiFriend.userId).items,
            friendItems),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
