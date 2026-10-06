import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

Future<void> _revealAction(WidgetTester tester, Finder action) async {
  if (action.evaluate().isEmpty) {
    await tester.scrollUntilVisible(action, 220,
        scrollable: find.byType(Scrollable).first, maxScrolls: 15);
  }
  expect(action, findsOneWidget);
  await tester.ensureVisible(action);
  // The feed scrolls under its glass header. Center the real button so a tap
  // cannot accidentally land in the app bar after ensureVisible aligns it.
  await Scrollable.ensureVisible(tester.element(action), alignment: .5);
  await tester.pumpAndSettle();
}

void _expectRetainedButton(WidgetTester tester, Finder action, IconData icon) {
  final button = tester.widget<TextButton>(action);
  expect(button.onPressed, isNotNull);
  expect(button.style?.minimumSize?.resolve(const <WidgetState>{}),
      const Size(48, 48));
  expect(button.style?.padding?.resolve(const <WidgetState>{}),
      const EdgeInsets.symmetric(horizontal: AppTokens.s2));
  expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
  expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
  final glyph = find.descendant(of: action, matching: find.byIcon(icon));
  expect(glyph, findsOneWidget);
  expect(tester.widget<Icon>(glyph).size, AppTokens.s6);
  final label = find.descendant(of: action, matching: find.byType(Text));
  expect(label, findsOneWidget);
  expect(tester.widget<Text>(label).style?.fontSize, AppTokens.captionFontSize);
}

MomentPost _visibleProjection(
        MomentsUiFixture fixture, MomentsUiSurface surface, String momentId) =>
    (surface == MomentsUiSurface.profile
            ? fixture.repository.userState(momentsUiSelf.userId).items
            : fixture.repository.feedState.items)
        .singleWhere((post) => post.momentId == momentId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    NavigationGlassController.instance.load();
  });

  for (final surface in MomentsUiSurface.values) {
    for (final dark in [false, true]) {
      testWidgets(
          '${surface.name} retains like and comment actions in ${dark ? 'dark' : 'light'}',
          (tester) async {
        final fixture = MomentsUiFixture();
        addTearDown(fixture.dispose);
        await prepareMomentsUiPhotos(tester, fixture);
        final repository = fixture.repository;
        final momentId = surface == MomentsUiSurface.profile
            ? momentsUiOwnPostId
            : momentsUiFriendPostId;
        if (surface == MomentsUiSurface.detail) {
          // Detail mutations must update the feed entity that was already read.
          await repository.loadFeed();
        }
        await mountMomentsUi(tester,
            fixture: fixture, surface: surface, dark: dark);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        });

        final like = find.byKey(ValueKey('moments_like_$momentId'));
        final comment = find.byKey(ValueKey('moments_comment_$momentId'));
        await _revealAction(tester, like);
        final before = repository.postById(momentId)!;
        _expectRetainedButton(
            tester,
            like,
            before.likedByMe
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded);
        await _revealAction(tester, comment);
        _expectRetainedButton(
            tester, comment, Icons.chat_bubble_outline_rounded);

        await _revealAction(tester, like);
        await tester.tap(like);
        await tester.pumpAndSettle();
        final liked = !before.likedByMe;
        expect(fixture.api.likeWrites, [
          {'momentId': momentId, 'liked': liked},
        ]);
        final afterLike = repository.postById(momentId)!;
        expect(afterLike.likedByMe, liked);
        expect(afterLike.version, before.version + 1);
        expect(afterLike.likeCount, before.likeCount + (liked ? 1 : -1));
        expect(
            afterLike.likesPreview
                .where((item) => item.user.userId == momentsUiSelf.userId),
            liked ? hasLength(1) : isEmpty);
        final likeProjection = _visibleProjection(fixture, surface, momentId);
        expect(likeProjection.likedByMe, liked);
        expect(likeProjection.version, afterLike.version);
        expect(likeProjection.likeCount, afterLike.likeCount);
        await _revealAction(tester, like);
        _expectRetainedButton(tester, like,
            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded);

        await _revealAction(tester, comment);
        await tester.tap(comment);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        final body = '${surface.name}页面的中文评论，${dark ? '深色' : '浅色'}主题。';
        await tester.enterText(find.byType(TextField), body);
        await tester.pump();
        final send = find.widgetWithText(FilledButton, '发送');
        expect(send, findsOneWidget);
        expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pumpAndSettle();

        expect(fixture.api.commentWrites, hasLength(1));
        final write = fixture.api.commentWrites.single;
        expect(write['momentId'], momentId);
        expect(write['text'], body);
        expect(write['clientRequestId'], isA<String>());
        expect((write['clientRequestId']! as String).trim(), isNotEmpty);
        expect(write['replyToCommentId'], isNull);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(TextField), findsNothing);

        final confirmed = repository
            .commentState(momentId)
            .items
            .singleWhere((item) => item.text == body);
        expect(confirmed.author.userId, momentsUiSelf.userId);
        final afterComment = repository.postById(momentId)!;
        expect(afterComment.version, afterLike.version + 1);
        expect(afterComment.commentCount, before.commentCount + 1);
        expect(
            afterComment.commentsPreview
                .where((item) => item.commentId == confirmed.commentId)
                .map((item) => item.text),
            [body]);
        final commentProjection =
            _visibleProjection(fixture, surface, momentId);
        expect(commentProjection.version, afterComment.version);
        expect(commentProjection.commentCount, afterComment.commentCount);
        expect(
            commentProjection.commentsPreview
                .where((item) => item.commentId == confirmed.commentId)
                .map((item) => item.text),
            [body]);
        await _revealAction(tester, comment);
        _expectRetainedButton(
            tester, comment, Icons.chat_bubble_outline_rounded);
        expect(
            find.descendant(
                of: comment,
                matching: find.text('${afterComment.commentCount}')),
            findsOneWidget);
        if (surface == MomentsUiSurface.detail) {
          expect(find.textContaining(body, findRichText: true), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
