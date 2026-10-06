import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';

import '../../pages/moments/support/moments_ui_fixture.dart';

const _denied = MomentsException('Old request lost permission',
    code: 'NOT_ALLOWED', permissionDenied: true);

void _expectFreshPost(MomentsUiFixture fixture) {
  final cached = fixture.repository.postById(momentsUiFriendPostId);
  expect(cached, isNotNull);
  expect(cached!.text, 'Fresh authorized content');
  expect(cached.version, 2);
  final inFeed = fixture.repository.feedState.items
      .firstWhere((post) => post.momentId == momentsUiFriendPostId);
  expect(inFeed.text, 'Fresh authorized content');
  expect(inFeed.version, 2);
}

Future<void> _refreshNewContent(MomentsUiFixture fixture) async {
  fixture.api.posts[momentsUiFriendPostId] = MomentPost.fromJson({
    ...fixture.api.posts[momentsUiFriendPostId]!.toJson(),
    'text': 'Fresh authorized content',
    'version': 2,
  });
  await fixture.repository.refreshAuthorization();
  _expectFreshPost(fixture);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'late detail success or permission error cannot invalidate refreshed content',
      () async {
    for (final fails in [false, true]) {
      final fixture = MomentsUiFixture();
      try {
        await fixture.repository.loadFeed();
        final oldPost = fixture.api.posts[momentsUiFriendPostId]!;
        final started = Completer<void>();
        final pending = Completer<MomentPost>();
        fixture.api.detailWork = (_) {
          started.complete();
          return pending.future;
        };
        final oldRequest = fixture.repository
            .loadDetail(momentsUiFriendPostId, trackForSync: false);
        final expectation = expectLater(
            oldRequest,
            throwsA(fails
                ? same(_denied)
                : isA<MomentsException>().having(
                    (error) => error.code, 'context code', 'CONTEXT_CHANGED')));
        await started.future;
        await _refreshNewContent(fixture);
        expect(fixture.api.detailRequests, [momentsUiFriendPostId]);
        if (fails) {
          pending.completeError(_denied);
        } else {
          pending.complete(oldPost);
        }
        await expectation;
        _expectFreshPost(fixture);
      } finally {
        fixture.dispose();
      }
    }
  });

  test(
      'late private-media permission error cannot invalidate refreshed content',
      () async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await fixture.repository.loadFeed();
    final started = Completer<void>();
    final pending = Completer<Uint8List>();
    fixture.api.mediaWork = (_, __) {
      started.complete();
      return pending.future;
    };
    final oldRequest = fixture.repository.downloadMedia(momentsUiPhotos.first);
    final expectation = expectLater(oldRequest, throwsA(same(_denied)));
    await started.future;
    await _refreshNewContent(fixture);
    expect(fixture.api.mediaRequests, ['preview-scenery:false']);
    pending.completeError(_denied);
    await expectation;
    _expectFreshPost(fixture);
  });
}
