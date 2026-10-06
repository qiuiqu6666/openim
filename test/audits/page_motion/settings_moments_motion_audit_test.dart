import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/secondary/favorite_detail_page.dart';
import 'package:openim/pages/moments/media/moments_media_grid.dart';
import 'package:openim/services/favorite_send_coordinator.dart';
import 'package:openim/services/moments_models.dart';

import '../../pages/favorites/support/favorite_ui_test_support.dart';
import '../../pages/moments/support/moments_ui_fixture.dart';
import '../../pages/moments/support/moments_ui_host.dart';
import '../../support/performance/render_test_fakes.dart';

// Diagnostic baselines for the page-motion audit, not assertions that these
// transitions are already fixed. The production widgets and image decoder run;
// only transport completion is controlled so the two visible frames are exact.
void main() {
  for (final sample in [momentsUiPhotos.first, momentsUiPhotos.last]) {
    for (final hasDimensions in [false, true]) {
      testWidgets(
          'audit: moments single image downstream geometry / '
          '${sample.mediaId} / metadata=$hasDimensions', (tester) async {
        final fixture = MomentsUiFixture();
        addTearDown(fixture.dispose);
        addTearDown(Get.reset);
        await prepareMomentsUiPhotos(tester, fixture);
        final response = Completer<Uint8List>();
        fixture.api.mediaWork = (_, __) => response.future;
        final media = hasDimensions
            ? sample
            : MomentMedia(
                mediaId: sample.mediaId,
                contentPath: sample.contentPath,
                thumbPath: sample.thumbPath);
        final post = MomentPost(
            momentId: 'motion-audit-post',
            author: momentsUiFriend,
            mediaList: [media]);
        const afterMedia = ValueKey('audit-content-after-moments-media');
        await tester.pumpWidget(renderTestHost(Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              MomentsMediaGrid(
                  repository: fixture.repository, post: post, onOpen: (_) {}),
              const Text('Content below the same post', key: afterMedia),
            ]),
          ),
        )));
        await tester.pump();
        final before = tester.getTopLeft(find.byKey(afterMedia));
        response.complete(fixture.api.mediaBytes[sample.mediaId]!);
        await settleVisibleMomentsUiMedia(tester);
        final after = tester.getTopLeft(find.byKey(afterMedia));
        final delta = after.dy - before.dy;
        if (hasDimensions) {
          expect(delta, closeTo(0, .01),
              reason: 'Supplied dimensions reserve the final image height.');
        } else {
          final finalHeight = sample == momentsUiPhotos.first ? 420.0 : 240.0;
          expect(delta, closeTo(finalHeight - 320 / 1.08, .01),
              reason: 'Decode changes an already visible post height.');
          expect(delta.abs(), greaterThan(50));
        }
        debugPrint('motion audit moments ${sample.mediaId} '
            'metadata=$hasDimensions downstream delta=${delta.toStringAsFixed(2)}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('audit: favorite detail send progress moves unchanged body',
      (tester) async {
    final repository = FavoriteUiRepository();
    addTearDown(repository.dispose);
    final pending = Completer<FavoriteSendResult>();
    await tester.pumpWidget(favoriteUiHost(FavoriteDetailPage(
      repository: repository,
      item: uiNote,
      onSend: (_) => pending.future,
    )));
    await tester.pumpAndSettle();
    final body = find.text('保留收藏正文');
    expect(body, findsOneWidget);
    final before = tester.getTopLeft(body);
    await tester.tap(find.byKey(const ValueKey('favorite-detail-send')));
    await tester.pump();
    final during = tester.getTopLeft(body);
    final progressHeight =
        tester.getSize(find.byType(LinearProgressIndicator)).height;
    expect(progressHeight, greaterThan(0));
    expect(during.dy - before.dy, closeTo(progressHeight, .01),
        reason: 'The pending-send indicator participates in the body Column.');
    pending.complete(const FavoriteSendResult(
        status: FavoriteSendStatus.failed, errorCode: 'CANCELLED'));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(body);
    expect(after.dy - before.dy, closeTo(0, .01));
    debugPrint('motion audit favorite detail body delta='
        '${(during.dy - before.dy).toStringAsFixed(2)}, '
        'settled delta=${(after.dy - before.dy).toStringAsFixed(2)}');
    expect(repository.saves, 0);
    expect(repository.singleDeletes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
