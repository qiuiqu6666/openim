import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/presentation/moments_post_card.dart';
import 'package:openim/pages/moments/presentation/moments_cover_header.dart';
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
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
