import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/moments/media/moments_media_image.dart';
import 'package:openim/pages/moments/media/moments_single_media_frame.dart';
import 'package:openim/services/moments_models.dart';

import '../../../support/performance/render_test_fakes.dart';
import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

void main() {
  testWidgets('decoded ratio survives metadata removal and resets by resource',
      (tester) async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    addTearDown(Get.reset);
    await prepareMomentsUiPhotos(tester, fixture);
    var media = momentsUiPhotos.first;
    late StateSetter update;
    const imageKey = ValueKey('single_media_image');
    await tester.pumpWidget(renderTestHost(Align(
      alignment: Alignment.topLeft,
      child: StatefulBuilder(builder: (_, setState) {
        update = setState;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 320,
            child: MomentsSingleMediaFrame(
              media: media,
              imageBuilder: (callback) => MomentsMediaImage(
                key: imageKey,
                repository: fixture.repository,
                media: media,
                onDimensions: callback,
              ),
            ),
          ),
        ]);
      }),
    )));
    await tester.pumpAndSettle();
    final original = tester.getSize(find.byKey(imageKey));
    expect(original.height, 420);
    expect(original.width / original.height, 576 / 1024);
    expect(fixture.api.mediaRequests, ['preview-scenery:true']);

    // Real Image.frameBuilder already supplied the decoded package dimensions.
    // An update omitting optional server metadata must not undo that report or
    // reload the unchanged resource, which only reports its dimensions once.
    update(() => media = const MomentMedia(
        mediaId: 'preview-scenery',
        contentPath: '/preview/scenery',
        thumbPath: '/preview/scenery-thumb'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(imageKey)), original);
    expect(fixture.api.mediaRequests, ['preview-scenery:true']);

    final pathResponse = Completer<Uint8List>();
    fixture.api.mediaWork = (_, __) => pathResponse.future;
    update(() => media = const MomentMedia(
        mediaId: 'preview-scenery',
        contentPath: '/preview/replaced-image',
        thumbPath: '/preview/replaced-thumb'));
    await tester.pump();
    final pendingPath = tester.getSize(find.byKey(imageKey));
    expect(pendingPath.width, 320);
    expect(pendingPath.height, closeTo(320 / 1.08, .01));
    expect(pendingPath, isNot(original));
    pathResponse.complete(fixture.api.mediaBytes['preview-cover']!);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(imageKey)), const Size(320, 240));

    final idResponse = Completer<Uint8List>();
    fixture.api.mediaWork = (_, __) => idResponse.future;
    update(() => media = const MomentMedia(
        mediaId: 'preview-other-resource',
        contentPath: '/preview/replaced-image',
        thumbPath: '/preview/replaced-thumb'));
    await tester.pump();
    final pendingId = tester.getSize(find.byKey(imageKey));
    expect(pendingId.width, 320);
    expect(pendingId.height, closeTo(320 / 1.08, .01));
    expect(fixture.api.mediaRequests, [
      'preview-scenery:true',
      'preview-scenery:true',
      'preview-other-resource:true',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    idResponse.complete(fixture.api.mediaBytes['preview-scenery']!);
    await tester.pumpAndSettle();
  });
}
