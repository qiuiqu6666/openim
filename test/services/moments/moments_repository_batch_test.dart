import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';

import '../../support/performance/render_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('20-post page only transitions loading and committed page once',
      () async {
    final api = RenderTestApi();
    final repository = renderTestRepository(api);
    addTearDown(repository.dispose);
    await repository.loadFeed();
    for (var i = 1; i < 50; i++) {
      await repository.loadFeed(refresh: false);
    }
    expect(repository.feedState.items.length, 1000);
    var notifications = 0;
    var intermediateCopies = 0;
    var previous = repository.feedState.items;
    repository.addListener(() {
      notifications++;
      final current = repository.feedState.items;
      if (!identical(previous, current) && current.length == 1000) {
        intermediateCopies++;
      }
      previous = current;
    });
    await repository.loadFeed(refresh: false);
    expect(intermediateCopies, 0);
    expect(notifications, 2);
    expect(repository.feedState.items.length, 1020);
  });

  test('batch preserves newest version, tombstones and album projections',
      () async {
    final api = RenderTestApi();
    final repository = renderTestRepository(api);
    addTearDown(repository.dispose);
    MomentPost post(String id, int version) => MomentPost(
          momentId: id,
          author: renderTestUser,
          version: version,
          text: 'version $version',
          likesPreview: const [
            MomentLike(user: MomentUser(userId: 'not-a-friend')),
          ],
          likeCount: 1,
        );
    api.albumWork = (_) async =>
        MomentsPageResult(items: [post('shared', 3), post('deleted', 2)]);
    await repository.loadUser('album');
    await repository.deletePost('deleted');
    final albumBefore = repository.userState('album').items;
    final observations = <List<MomentPost>>[];
    repository.addListener(() {
      final album = repository.userState('album').items;
      if (!identical(albumBefore, album)) observations.add(album);
    });
    api.feedWork = (_) async => MomentsPageResult(items: [
          post('shared', 2),
          post('shared', 4),
          post('shared', 3),
          post('deleted', 2),
          post('new', 1),
        ]);
    await repository.loadFeed();
    expect(
        repository.feedState.items.map((p) => p.momentId), ['shared', 'new']);
    expect(repository.postById('shared')!.version, 4);
    expect(repository.postById('deleted'), isNull);
    final album = repository.userState('album').items;
    expect(album.single.version, 4);
    expect(observations, hasLength(1));
    expect(album.single.likesPreview, isEmpty,
        reason: 'Batching cannot bypass actor visibility filtering');
    expect(album.single.interactionCountsTrusted, isFalse);
  });

  test('stale page arriving after authorization invalidation never batches',
      () async {
    final api = RenderTestApi();
    final repository = renderTestRepository(api);
    addTearDown(repository.dispose);
    final scope = repository.sessionScope;
    api.feedWork = (_) async {
      repository.resetSession();
      return const MomentsPageResult(items: [
        MomentPost(momentId: 'late', author: renderTestUser),
      ]);
    };
    await expectLater(repository.loadFeed(), throwsA(isA<MomentsException>()));
    expect(repository.isSessionCurrent(scope), isFalse);
    expect(repository.postById('late'), isNull);
    expect(repository.feedState.items, isEmpty);
  });
}
