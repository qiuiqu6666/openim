import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';

import '../../pages/moments/support/moments_ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mutation refreshes do not register closed details for future sync',
      () async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    await fixture.repository.loadFeed();
    await fixture.repository.setLiked(momentsUiFriendPostId, true);
    fixture.api.detailRequests.clear();
    await fixture.repository.refreshAuthorization();
    expect(fixture.api.detailRequests, isEmpty);
  });

  test('same detail is retained until the final page releases it', () async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    final repository = fixture.repository;
    final scope = repository.sessionScope;
    repository.retainDetail(momentsUiFriendPostId);
    repository.retainDetail(momentsUiFriendPostId);
    await repository.loadDetail(momentsUiFriendPostId, trackForSync: false);
    repository.releaseDetail(momentsUiFriendPostId, sessionScope: scope);
    fixture.api.detailRequests.clear();
    await repository.refreshAuthorization();
    expect(fixture.api.detailRequests, [momentsUiFriendPostId]);
    repository.releaseDetail(momentsUiFriendPostId, sessionScope: scope);
    fixture.api.detailRequests.clear();
    await repository.refreshAuthorization();
    expect(fixture.api.detailRequests, isEmpty);
  });

  test('old account release cannot remove a new account detail subscription',
      () async {
    final fixture = MomentsUiFixture();
    addTearDown(fixture.dispose);
    final repository = fixture.repository;
    final oldScope = repository.sessionScope;
    repository.retainDetail(momentsUiFriendPostId);
    fixture.ownerUserId = 'another-account';
    repository.resetSession();
    repository.retainDetail(momentsUiFriendPostId);
    repository.releaseDetail(momentsUiFriendPostId, sessionScope: oldScope);
    await repository.refreshAuthorization();
    expect(fixture.api.detailRequests, [momentsUiFriendPostId]);
  });

  test('confirmed friendship removal clears all private content in one update',
      () async {
    final api = MomentsUiApi(posts: momentsUiPosts());
    var friends = [momentsUiFriend, momentsUiSecondFriend];
    final repository = MomentsRepository(
        api: api,
        userIdProvider: () => momentsUiSelf.userId,
        friendLoader: () async => friends,
        subscribeToSdk: false);
    addTearDown(repository.dispose);
    await repository.loadFeed();
    await repository.loadComments(momentsUiFriendPostId);
    await repository.loadNotifications();
    var notifications = 0;
    repository.addListener(() => notifications++);
    friends = [];
    await repository.loadFriends(force: true);
    expect(repository.postsById, isEmpty);
    expect(repository.feedState.items, isEmpty);
    expect(repository.friends, isEmpty);
    expect(repository.commentState(momentsUiFriendPostId).items, isEmpty);
    expect(repository.notifications, isEmpty);
    expect(repository.unreadCount, 0);
    expect(notifications, 1);
  });

  test('confirmed removal rejects earlier feed and private media responses',
      () async {
    final api = MomentsUiApi(posts: momentsUiPosts());
    var friends = [momentsUiFriend, momentsUiSecondFriend];
    final repository = MomentsRepository(
        api: api,
        userIdProvider: () => momentsUiSelf.userId,
        friendLoader: () async => friends,
        subscribeToSdk: false);
    addTearDown(repository.dispose);
    await repository.loadFeed();
    final before = repository.authorizationScope;
    final feedGate = Completer<MomentsPageResult<MomentPost>>();
    final mediaGate = Completer<Uint8List>();
    api.feedWork = (_) => feedGate.future;
    api.mediaWork = (_, __) => mediaGate.future;
    final feed =
        expectLater(repository.loadFeed(), throwsA(isA<MomentsException>()));
    final media = expectLater(repository.downloadMedia(momentsUiPhotos.first),
        throwsA(isA<MomentsException>()));
    while (api.feedCursors.length < 2 || api.mediaRequests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    friends = [momentsUiSecondFriend];
    await repository.loadFriends(force: true);
    expect(repository.authorizationScope, isNot(before));
    expect(repository.friends, [momentsUiSecondFriend]);
    expect(repository.postsById, isEmpty);
    feedGate.complete(MomentsPageResult(items: momentsUiPosts()));
    mediaGate.complete(Uint8List.fromList([1, 2, 3]));
    await Future.wait([feed, media]);
    expect(repository.postsById, isEmpty);
    expect(repository.feedState.items, isEmpty);
  });
}
