import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_widgets.dart';
import 'package:openim/pages/moments/presentation/moments_engagement_panel.dart';
import 'package:openim/pages/moments/presentation/moments_cover_header.dart';
import 'package:openim/pages/moments/presentation/moments_profile_timeline.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

Finder _key(String name) => find.byKey(ValueKey(name));
Finder _post(String id) => find.byWidgetPredicate(
    (widget) => widget is MomentsPostCard && widget.post.momentId == id);
Finder _inside(Finder parent, Type type) =>
    find.descendant(of: parent, matching: find.byType(type));

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });

  for (final dark in [false, true]) {
    testWidgets('feed has full cover and reference card geometry ($dark)',
        (tester) async {
      final fixture = MomentsUiFixture();
      addTearDown(fixture.dispose);
      await prepareMomentsUiPhotos(tester, fixture);
      await mountMomentsUi(tester, fixture: fixture, dark: dark);

      final cover = _key('moments_cover');
      expect(tester.getRect(cover), const Rect.fromLTWH(0, 0, 375, 250));
      expect(find.byType(TitleBar), findsNothing);
      expect(find.byType(GlassAppBar), findsNothing);
      final title = _key('moments_header_title');
      expect(tester.getTopLeft(title), const Offset(28, 88));
      final titleWidget = tester.widget<Text>(title);
      expect(titleWidget.style!.fontSize, 24);
      expect(titleWidget.style!.fontWeight, FontWeight.w300);
      expect(titleWidget.style!.color, Colors.white);
      final avatar = _key('moments_header_avatar');
      expect(tester.getSize(avatar), const Size(72, 72));
      expect(tester.getTopLeft(avatar), const Offset(284, 153));
      final avatarBorder = find.ancestor(
          of: avatar,
          matching: find.byWidgetPredicate((widget) =>
              widget is Container &&
              widget.padding == const EdgeInsets.all(3)));
      expect(tester.getSize(avatarBorder.first), const Size(78, 78));
      final coverButtons = _inside(cover, IconButton);
      expect(coverButtons, findsAtLeastNWidgets(3));
      for (final element in coverButtons.evaluate()) {
        final button = element.widget as IconButton;
        expect(button.color, Colors.white);
        final bounds = tester.getSize(find.byWidget(button));
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
      }
      expect(
          find.descendant(of: cover, matching: find.text('1')), findsOneWidget);
      expect(
          tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          dark ? const Color(0xFF101114) : const Color(0xFFF5F6F8));

      final post = _post(momentsUiFriendPostId);
      expect(tester.getRect(post).left, 10);
      expect(tester.getSize(post).width, 355);
      final material = tester.widget<Material>(_inside(post, Material).first);
      expect(material.color, dark ? const Color(0xFF1B1D22) : Colors.white);
      expect(material.borderRadius, BorderRadius.circular(18));
      final padding = tester.widget<Padding>(_inside(post, Padding).first);
      expect(padding.padding, const EdgeInsets.fromLTRB(14, 12, 14, 6));
      expect(
          tester.getSize(_inside(post, AvatarView).first), const Size(40, 40));
      final name = find.descendant(of: post, matching: find.text('小林'));
      final nameWidget = tester.widget<Text>(name);
      expect(nameWidget.style!.fontSize, 16);
      expect(nameWidget.style!.fontWeight, FontWeight.w700);
      final body = find.descendant(
          of: post,
          matching: find.text(fixture.api.posts[momentsUiFriendPostId]!.text));
      final textWidget = tester.widget<Text>(body);
      expect(textWidget.style!.fontSize, 15);
      expect(textWidget.style!.height, 1.5);
      expect(textWidget.maxLines, isNull);
      final headerRow = _inside(post, Row).first;
      expect(
          tester.getTopLeft(body).dy - tester.getBottomLeft(headerRow).dy, 10);
      final media = [
        for (var i = 0; i < 3; ++i)
          tester.getRect(_key('moments_media_${momentsUiFriendPostId}_$i')),
      ];
      expect(media[0].top, media[1].top);
      expect(media[1].top, media[2].top);
      expect(media[1].left - media[0].right, closeTo(4, .01));
      expect(media[2].left - media[1].right, closeTo(4, .01));
      final panel = _inside(post, MomentsEngagementPanel);
      final likes = _inside(panel, AvatarView);
      expect(likes, findsNWidgets(2));
      expect(tester.getSize(likes.first), const Size(24, 24));
      final comment = tester
          .widget<MomentsCommentText>(_inside(panel, MomentsCommentText).first);
      final richText =
          tester.widget<Text>(_inside(find.byWidget(comment), Text).first);
      expect(richText.style!.fontSize, 13);
      expect(richText.style!.height, 1.25);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  }

  testWidgets('four images stay in three columns', (tester) async {
    const fourth =
        MomentMedia(mediaId: 'preview-fourth', width: 576, height: 1024);
    final base = momentsUiPosts().first;
    final post = MomentPost.fromJson({
      ...base.toJson(),
      'mediaList':
          [...base.mediaList, fourth].map((item) => item.toJson()).toList(),
    });
    final fixture = MomentsUiFixture(posts: [post]);
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    fixture.api.mediaBytes[fourth.mediaId] =
        fixture.api.mediaBytes[momentsUiPhotos.first.mediaId]!;
    await mountMomentsUi(tester, fixture: fixture);
    final first = tester.getRect(_key('moments_media_${post.momentId}_0'));
    final third = tester.getRect(_key('moments_media_${post.momentId}_2'));
    final last = tester.getRect(_key('moments_media_${post.momentId}_3'));
    expect(first.top, third.top);
    expect(first.left, last.left);
    expect(last.top - first.bottom, closeTo(4, .01));
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('single long image uses its ratio and caps feed height',
      (tester) async {
    const tall =
        MomentMedia(mediaId: 'preview-scenery', width: 576, height: 5760);
    final base = momentsUiPosts().first;
    final post = MomentPost.fromJson({
      ...base.toJson(),
      'mediaList': [tall.toJson()],
    });
    final fixture = MomentsUiFixture(posts: [post]);
    addTearDown(fixture.dispose);
    await prepareMomentsUiPhotos(tester, fixture);
    await mountMomentsUi(tester, fixture: fixture);
    final image = tester.getSize(_key('moments_media_${post.momentId}_0'));
    expect(image.width, lessThanOrEqualTo(327));
    expect(image.height, 420);
    expect(image.width / image.height, closeTo(.1, .001));
    expect(find.text('长图'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  for (final dark in [false, true]) {
    testWidgets('album groups days and uses 64/104 timeline geometry ($dark)',
        (tester) async {
      final fixture = MomentsUiFixture();
      addTearDown(fixture.dispose);
      await prepareMomentsUiPhotos(tester, fixture);
      await mountMomentsUi(tester,
          fixture: fixture, surface: MomentsUiSurface.profile, dark: dark);
      final first = _key('moments_album_post_$momentsUiOwnPostId');
      final sameDay = _key('moments_album_post_preview-own-same-day');
      final previousDay = _key('moments_album_post_preview-own-previous-day');
      final date = _key('moments_album_day_20261003');
      expect(date, findsOneWidget);
      expect(tester.getSize(date).width, 64);
      expect(_inside(sameDay, MomentsTimelineDate), findsNothing);
      expect(tester.widget<MomentsProfileTimelineItem>(first).showDate, isTrue);
      expect(
          tester.widget<MomentsProfileTimelineItem>(sameDay).showDate, isFalse);
      final collage = _inside(first, MomentsTimelineCollage);
      expect(tester.getSize(collage), const Size(104, 104));
      expect(
          tester.getTopLeft(collage).dx - tester.getBottomRight(date).dx, 12);
      final body = find.descendant(
          of: first,
          matching: find.text(fixture.api.posts[momentsUiOwnPostId]!.text));
      final bodyWidget = tester.widget<Text>(body);
      expect(bodyWidget.style!.fontSize, 16);
      expect(bodyWidget.maxLines, 3);
      expect(
          tester.getTopLeft(body).dx - tester.getBottomRight(collage).dx, 12);
      expect(tester.getTopLeft(body).dy, tester.getTopLeft(collage).dy);
      expect(find.byKey(ValueKey('moments_like_$momentsUiOwnPostId')),
          findsOneWidget);
      expect(find.byKey(ValueKey('moments_comment_$momentsUiOwnPostId')),
          findsOneWidget);
      if (previousDay.evaluate().isEmpty) {
        await tester.scrollUntilVisible(previousDay, 200,
            scrollable: find.byType(Scrollable).first);
      }
      expect(tester.widget<MomentsProfileTimelineItem>(previousDay).showDate,
          isTrue);
      expect(_inside(previousDay, MomentsTimelineDate), findsOneWidget);
      expect(fixture.api.feedCursors, isEmpty);
      expect(fixture.api.albumRequests, [momentsUiSelf.userId]);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  }

  for (final dark in [false, true]) {
    for (final surface in MomentsUiSurface.values) {
      testWidgets('${surface.name} supports 320 wide and 2x text ($dark)',
          (tester) async {
        final fixture = MomentsUiFixture();
        addTearDown(fixture.dispose);
        await prepareMomentsUiPhotos(tester, fixture);
        await mountMomentsUi(tester,
            fixture: fixture,
            surface: surface,
            dark: dark,
            size: const Size(320, 812),
            textScale: 2);
        expect(tester.takeException(), isNull);
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 3; ++i) {
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await _close(tester);
      });
    }
  }

  for (final size in [const Size(800, 900), const Size(812, 375)]) {
    for (final dark in [false, true]) {
      testWidgets('all pages fit ${size.width}x${size.height} ($dark)',
          (tester) async {
        for (final surface in MomentsUiSurface.values) {
          final fixture = MomentsUiFixture();
          addTearDown(fixture.dispose);
          await prepareMomentsUiPhotos(tester, fixture);
          await mountMomentsUi(tester,
              fixture: fixture, surface: surface, dark: dark, size: size);
          if (surface == MomentsUiSurface.detail) {
            expect(tester.getSize(_post(momentsUiFriendPostId)).width,
                lessThanOrEqualTo(640));
            final action = find.widgetWithText(OutlinedButton, '写评论…');
            expect(tester.getSize(action).width, lessThanOrEqualTo(608));
            expect(tester.getCenter(action).dx, size.width / 2);
          } else {
            final cover = tester.getRect(_key('moments_cover'));
            expect(cover.width, 640);
            expect(cover.left, (size.width - 640) / 2);
            expect(cover.top, 0);
            if (surface == MomentsUiSurface.feed) {
              expect(tester.getSize(_post(momentsUiFriendPostId)).width, 620);
            } else {
              final album = _key('moments_album_post_$momentsUiOwnPostId');
              if (album.evaluate().isEmpty) {
                await tester.scrollUntilVisible(album, 150,
                    scrollable: find.byType(Scrollable).first);
              }
              expect(tester.getSize(album).width, 640);
            }
          }
          expect(tester.takeException(), isNull);
          final scrollable = find.byType(Scrollable).first;
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _close(tester);
        }
      });
    }
  }

  for (final dark in [false, true]) {
    for (final reducedMotion in [false, true]) {
      testWidgets(
          'cover overscroll respects reduced motion $reducedMotion ($dark)',
          (tester) async {
        final fixture = MomentsUiFixture();
        addTearDown(fixture.dispose);
        await prepareMomentsUiPhotos(tester, fixture);
        await mountMomentsUi(tester,
            fixture: fixture, dark: dark, reducedMotion: reducedMotion);
        final controller = tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!;
        controller.jumpTo(-80);
        await tester.pump();
        final cover = _key('moments_cover');
        final transform = tester.widget<Transform>(find
            .descendant(
                of: find.byType(MomentsCoverHeader),
                matching: find.byType(Transform))
            .first);
        if (reducedMotion) {
          expect(tester.getSize(cover).height, 250);
          expect(transform.transform.getMaxScaleOnAxis(), 1);
        } else {
          expect(tester.getSize(cover).height, greaterThan(250));
          expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));
        }
        expect(tester.takeException(), isNull);
        await _close(tester);
      });
    }
  }
}
