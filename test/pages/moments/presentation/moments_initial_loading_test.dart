import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 3; ++i) {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });

  for (final surface in MomentsUiSurface.values) {
    for (final dark in [false, true]) {
      testWidgets('${surface.name} keeps initial capability loading ($dark)',
          (tester) async {
        final fixture = MomentsUiFixture();
        addTearDown(fixture.dispose);
        await prepareMomentsUiPhotos(tester, fixture);
        final gate = Completer<MomentsCapabilities>();
        fixture.api.capabilitiesWork = () => gate.future;
        await mountMomentsUi(tester,
            fixture: fixture, surface: surface, dark: dark, settle: false);
        await _flush(tester);
        expect(fixture.api.capabilityRequests, 1);
        expect(fixture.api.feedCursors, isEmpty);
        expect(fixture.api.albumRequests, isEmpty);
        expect(fixture.api.detailRequests, isEmpty);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        for (final post in fixture.api.posts.values) {
          expect(find.text(post.text), findsNothing);
        }

        gate.complete(MomentsCapabilities.fromJson({'supportsMoments': true}));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (surface == MomentsUiSurface.feed) {
          expect(fixture.api.feedCursors, [null]);
          expect(fixture.api.albumRequests, isEmpty);
          expect(find.text(fixture.api.posts[momentsUiFriendPostId]!.text),
              findsOneWidget);
        } else if (surface == MomentsUiSurface.profile) {
          expect(fixture.api.albumRequests, [momentsUiSelf.userId]);
          expect(fixture.api.feedCursors, isEmpty);
          expect(find.text(fixture.api.posts[momentsUiOwnPostId]!.text),
              findsOneWidget);
        } else {
          expect(fixture.api.detailRequests, [momentsUiFriendPostId]);
          expect(fixture.api.feedCursors, isEmpty);
          expect(find.text(fixture.api.posts[momentsUiFriendPostId]!.text),
              findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }

  for (final accountChange in [true, false]) {
    testWidgets(
        'late initial feed is hidden after '
        '${accountChange ? 'account' : 'server'} change', (tester) async {
      final fixture = MomentsUiFixture();
      addTearDown(fixture.dispose);
      await prepareMomentsUiPhotos(tester, fixture);
      final oldResponse = Completer<MomentsPageResult<MomentPost>>();
      fixture.api.feedWork = (_) => oldResponse.future;
      await mountMomentsUi(tester, fixture: fixture, settle: false);
      await _flush(tester);
      expect(fixture.api.feedCursors, [null]);
      expect(find.text(fixture.api.posts[momentsUiFriendPostId]!.text),
          findsNothing);

      if (accountChange) {
        fixture.ownerUserId = 'preview-next-owner';
      } else {
        fixture.server = 'https://moments-next-server.example';
      }
      fixture.api.feedWork = (_) async => const MomentsPageResult(items: []);
      await fixture.repository.refreshAuthorization();
      await _flush(tester);
      oldResponse.complete(MomentsPageResult(items: momentsUiPosts()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('登录状态已变化'), findsOneWidget);
      expect(find.text(fixture.api.posts[momentsUiFriendPostId]!.text),
          findsNothing);
      expect(fixture.repository.postsById, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
