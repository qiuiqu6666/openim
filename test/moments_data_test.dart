import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';

const me = MomentUser(userId: 'me', nickname: 'Me');
const friend = MomentUser(userId: 'friend', nickname: 'Friend');
const stranger = MomentUser(userId: 'stranger', nickname: 'Stranger');
const enabled = MomentsCapabilities(
    enabled: true,
    readEnabled: true,
    publishEnabled: true,
    interactionsEnabled: true,
    settingsEnabled: true);

MomentPost post(String id,
        {MomentUser author = me,
        List<MomentLike> likes = const [],
        List<MomentComment> comments = const [],
        int version = 1}) =>
    MomentPost(
        momentId: id,
        author: author,
        text: 'text',
        likesPreview: likes,
        commentsPreview: comments,
        likeCount: likes.length,
        commentCount: comments.length,
        createdAt: 1790985600000,
        version: version,
        canLike: true,
        canComment: true,
        canDelete: author.userId == 'me');
MomentNotification notification(String id,
        {MomentUser actor = friend, MomentUser? target, int seq = 100}) =>
    MomentNotification(
        notificationId: id,
        actor: actor,
        momentId: 'post',
        replyToUser: target,
        seq: seq);

class FakeMomentsApi extends MomentsApi {
  FakeMomentsApi()
      : super(
            baseUrl: 'https://business.example/chat',
            tokenProvider: () => 'business-token');
  MomentsCapabilities caps = enabled;
  int capsCalls = 0, feedCalls = 0;
  Future<MomentsPageResult<MomentPost>> Function(String?)? feedWork;
  Future<MomentPost> Function(String)? detailWork;
  Future<void> Function(String, bool)? likeWork;
  Future<MomentsPageResult<MomentLike>> Function(String, String?)? likesWork;
  Future<MomentsPageResult<MomentNotification>> Function(String?)?
      notificationWork;
  Future<int> Function(int?, String?)? readWork;
  @override
  Future<MomentsCapabilities> capabilities() async {
    capsCalls++;
    return caps;
  }

  @override
  Future<MomentsPageResult<MomentPost>> feed(
      {String? cursor, int pageSize = 20}) async {
    feedCalls++;
    return feedWork?.call(cursor) ?? MomentsPageResult(items: [post('post')]);
  }

  @override
  Future<MomentPost> detail(String id) async =>
      detailWork?.call(id) ?? post(id);
  @override
  Future<void> setLiked(String id, bool liked) async {
    await likeWork?.call(id, liked);
  }

  @override
  Future<MomentsPageResult<MomentLike>> likes(String id,
          {String? cursor, int pageSize = 20}) async =>
      likesWork?.call(id, cursor) ?? const MomentsPageResult(items: []);

  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
          {String? cursor, int pageSize = 20}) async =>
      notificationWork?.call(cursor) ??
      MomentsPageResult(
          items: [notification('n')],
          unreadCount: 1,
          readThroughSeq: 100,
          seenWatermark: 'watermark-100');
  @override
  Future<int> markNotificationsRead(
          {List<String> notificationIds = const [],
          int? readThroughSeq,
          String? seenWatermark}) async =>
      readWork?.call(readThroughSeq, seenWatermark) ?? 0;
  @override
  Future<MomentComment> createComment(String id,
          {required String text,
          required String clientRequestId,
          String? replyToCommentId}) async =>
      MomentComment(commentId: 'comment', author: me, text: text, createdAt: 1);
}

MomentsRepository repository(FakeMomentsApi api,
        {String Function()? owner,
        Future<List<MomentUser>> Function()? friendLoader}) =>
    MomentsRepository(
        api: api,
        userIdProvider: owner ?? () => 'me',
        environmentProvider: () => 'https://business.example/chat',
        friendLoader: friendLoader ?? () async => [friend],
        subscribeToSdk: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('repository privacy, generations and watermarks', () {
    test('capabilities closed blocks real reads and can be probed on retry',
        () async {
      final api = FakeMomentsApi()..caps = const MomentsCapabilities();
      final repo = repository(api);
      addTearDown(repo.dispose);
      await expectLater(
          repo.loadFeed(),
          throwsA(isA<MomentsException>()
              .having((e) => e.unavailable, 'unavailable', true)));
      expect(api.feedCalls, 0);
      expect(repo.feedState.items, isEmpty);
      api.caps = enabled;
      await repo.loadFeed();
      expect(api.capsCalls, 2);
      expect(repo.feedState.items, hasLength(1));
    });
    test('supportsMoments enables reads without any protocolVersion', () async {
      final api = FakeMomentsApi()
        ..caps = MomentsCapabilities.fromJson({'supportsMoments': true});
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadFeed();
      expect(api.feedCalls, 1);
      expect(repo.feedState.items, hasLength(1));
    });
    test('author gets no stranger exception; reply target is filtered too',
        () async {
      final api = FakeMomentsApi();
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadFriends();
      repo.applyPost(post('mine', likes: [
        const MomentLike(user: stranger),
        const MomentLike(user: friend)
      ], comments: [
        const MomentComment(
            commentId: 'stranger', author: stranger, text: 'hidden'),
        const MomentComment(
            commentId: 'friend', author: friend, text: 'visible'),
        const MomentComment(
            commentId: 'reply',
            author: me,
            text: 'hidden reply',
            replyToCommentId: 'target',
            replyToUser: stranger),
      ]));
      final visible = repo.postById('mine')!;
      expect(visible.likesPreview.map((like) => like.user.userId), ['friend']);
      expect(visible.commentsPreview.map((comment) => comment.commentId),
          ['friend']);
      expect(visible.interactionCountsTrusted, false);
      expect(
          repo.commentVisible(const MomentComment(
              commentId: 'missing-target',
              author: me,
              replyToCommentId: 'target',
              replyTargetDeleted: true)),
          false);
    });
    test('deleted target is anonymous but still requires a known friend',
        () async {
      final repo = repository(FakeMomentsApi());
      addTearDown(repo.dispose);
      await repo.loadFriends();
      final reply = MomentComment.fromJson({
        'commentId': 'reply',
        'author': me.toJson(),
        'text': 'surviving reply',
        'replyToCommentId': 'deleted',
        'replyTargetDeleted': true,
        'replyToUser': {
          'userId': 'friend',
          'nickname': 'old private name',
          'avatarUrl': 'old private photo',
          'remark': 'old private remark'
        }
      });
      expect(repo.commentVisible(reply), true);
      expect(reply.replyToUser!.toJson(),
          {'userId': 'friend', 'nickname': '', 'avatarUrl': '', 'remark': ''});
      expect(reply.replyTargetLabel, '已删除评论');
      expect(reply.toJson().toString(), isNot(contains('old private')));
      for (final target in [null, stranger]) {
        expect(
            repo.commentVisible(MomentComment(
                commentId: 'unauthorized',
                author: me,
                replyToCommentId: 'deleted',
                replyTargetDeleted: true,
                replyToUser: target)),
            false);
      }
      final unknown = repository(FakeMomentsApi(),
          friendLoader: () async => throw StateError('SDK offline'));
      addTearDown(unknown.dispose);
      expect(unknown.commentVisible(reply), false);
    });
    test('deleted reply notification sanitizes target and cannot bypass ACL',
        () async {
      MomentNotification deletedNotification(String id, MomentUser? target) =>
          MomentNotification.fromJson({
            'notificationId': id,
            'actor': friend.toJson(),
            'momentId': 'post',
            'replyToUser': target?.toJson(),
            'comment': {
              'commentId': id,
              'author': friend.toJson(),
              'text': 'reply',
              'replyToCommentId': 'deleted',
              'replyTargetDeleted': true,
              'replyToUser': target?.toJson()
            }
          });
      final api = FakeMomentsApi()
        ..notificationWork = (_) async => MomentsPageResult(items: [
              deletedNotification('authorized', friend),
              deletedNotification('missing', null),
              deletedNotification('stranger', stranger)
            ], unreadCount: 3);
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadNotifications();
      expect(repo.notifications.map((n) => n.notificationId), ['authorized']);
      expect(repo.notifications.single.replyToUser!.nickname, isEmpty);
      expect(repo.notifications.single.comment!.replyTargetLabel, '已删除评论');
      expect(repo.unreadCount, 0);
      expect(repo.notificationsCountsTrusted, false);
    });
    test('likes paging uses friend projection and suppresses invalid totals',
        () async {
      String? submittedCursor;
      final api = FakeMomentsApi()
        ..likesWork = (_, cursor) async {
          submittedCursor = cursor;
          return const MomentsPageResult(items: [
            MomentLike(user: me),
            MomentLike(user: friend),
            MomentLike(user: stranger)
          ], hasMore: true, nextCursor: 'next');
        };
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadFriends();
      repo.applyPost(post('post', likes: [const MomentLike(user: friend)]));
      expect(repo.postById('post')!.interactionCountsTrusted, true);
      final page = await repo.loadLikes('post', cursor: 'current');
      expect(submittedCursor, 'current');
      expect(page.items.map((like) => like.user.userId), ['me', 'friend']);
      expect(page.nextCursor, 'next');
      expect(page.hasMore, true);
      expect(repo.postById('post')!.interactionCountsTrusted, false);
    });
    test('likes response is discarded when permission context changes',
        () async {
      final pending = Completer<MomentsPageResult<MomentLike>>();
      final api = FakeMomentsApi()..likesWork = (_, __) => pending.future;
      final repo = repository(api);
      addTearDown(repo.dispose);
      final load = repo.loadLikes('post');
      await Future<void>.delayed(Duration.zero);
      await repo.refreshAuthorization();
      pending
          .complete(const MomentsPageResult(items: [MomentLike(user: friend)]));
      await expectLater(
          load,
          throwsA(isA<MomentsException>()
              .having((e) => e.permissionDenied, 'changed permission', true)));
      expect(repo.postById('post')!.likesPreview, isEmpty);
    });
    test('likes response is discarded after account changes', () async {
      final pending = Completer<MomentsPageResult<MomentLike>>();
      final api = FakeMomentsApi()..likesWork = (_, __) => pending.future;
      var owner = 'me';
      final repo = repository(api, owner: () => owner);
      addTearDown(repo.dispose);
      final load = repo.loadLikes('post');
      await Future<void>.delayed(Duration.zero);
      owner = 'other';
      pending
          .complete(const MomentsPageResult(items: [MomentLike(user: friend)]));
      await expectLater(
          load,
          throwsA(isA<MomentsException>()
              .having((e) => e.authRequired, 'changed account', true)));
    });
    test('ordinary viewer never retains an author audience list', () async {
      final api = FakeMomentsApi();
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadFriends();
      repo.applyPost(MomentPost(
          momentId: 'friend-post',
          author: friend,
          audienceUserIds: const ['secret'],
          version: 1));
      expect(repo.postById('friend-post')!.audienceUserIds, isEmpty);
    });
    test(
        'positive server counts without their required preview are not trusted',
        () async {
      final api = FakeMomentsApi();
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadFriends();
      repo.applyPost(const MomentPost(
          momentId: 'inconsistent',
          author: friend,
          likeCount: 5,
          commentCount: 3));
      expect(repo.postById('inconsistent')!.interactionCountsTrusted, false);
    });
    test('newer refresh wins and old completion cannot restore its rows',
        () async {
      final api = FakeMomentsApi();
      final first = Completer<MomentsPageResult<MomentPost>>();
      final second = Completer<MomentsPageResult<MomentPost>>();
      api.feedWork = (_) => api.feedCalls == 1 ? first.future : second.future;
      final repo = repository(api);
      addTearDown(repo.dispose);
      final oldLoad = repo.loadFeed();
      await Future<void>.delayed(Duration.zero);
      final newLoad = repo.loadFeed();
      await Future<void>.delayed(Duration.zero);
      second.complete(MomentsPageResult(items: [post('new')]));
      await newLoad;
      first.complete(MomentsPageResult(items: [post('old')]));
      await oldLoad;
      expect(repo.feedState.items.map((item) => item.momentId), ['new']);
      expect(repo.postById('old'), isNull);
    });
    test('switching account discards late response and clears shared entities',
        () async {
      final api = FakeMomentsApi();
      final pending = Completer<MomentsPageResult<MomentPost>>();
      api.feedWork = (_) => pending.future;
      var owner = 'me';
      final repo = repository(api, owner: () => owner);
      addTearDown(repo.dispose);
      final load = repo.loadFeed();
      await Future<void>.delayed(Duration.zero);
      owner = 'other';
      pending.complete(MomentsPageResult(items: [post('private')]));
      await expectLater(
          load,
          throwsA(isA<MomentsException>()
              .having((e) => e.authRequired, 'changed account', true)));
      expect(repo.postsById, isEmpty);
      expect(repo.feedState.items, isEmpty);
    });
    test('permission denied during mutation purges cached private content',
        () async {
      final api = FakeMomentsApi();
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadFeed();
      api.likeWork = (_, __) async =>
          throw const MomentsException('revoked', permissionDenied: true);
      await expectLater(
          repo.setLiked('post', true), throwsA(isA<MomentsException>()));
      expect(repo.postsById, isEmpty);
      expect(repo.feedState.items, isEmpty);
      expect(repo.feedState.error, isA<MomentsException>());
    });
    test('confirmed comment is added to the detail comment state', () async {
      final api = FakeMomentsApi();
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadFriends();
      await repo.addComment('post',
          text: 'confirmed', clientRequestId: 'stable-comment');
      expect(repo.commentState('post').items.map((item) => item.commentId),
          ['comment']);
    });
    test('notification actor and target are filtered; total is not invented',
        () async {
      final api = FakeMomentsApi()
        ..notificationWork = (_) async => MomentsPageResult(
                items: [
                  notification('ok'),
                  notification('hidden', actor: stranger),
                  notification('reply-hidden', target: stranger)
                ],
                unreadCount: 88,
                seenWatermark: 'watermark',
                readThroughSeq: 100);
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadNotifications();
      expect(repo.notifications.map((item) => item.notificationId), ['ok']);
      expect(repo.notificationsCountsTrusted, false);
      expect(repo.unreadCount, 0);
    });
    test(
        'friendship lookup failure is retryable rather than a fake empty inbox',
        () async {
      final api = FakeMomentsApi();
      final repo = repository(api,
          friendLoader: () async => throw StateError('SDK offline'));
      addTearDown(repo.dispose);
      await expectLater(
          repo.loadNotifications(),
          throwsA(isA<MomentsException>()
              .having((e) => e.code, 'code', 'FRIENDSHIP_UNAVAILABLE')));
      expect(repo.notificationsError, isA<MomentsException>());
      expect(repo.notifications, isEmpty);
      expect(repo.unreadCount, 0);
    });
    test('new notifications arriving during read-all keep their unread state',
        () async {
      final api = FakeMomentsApi();
      final read = Completer<int>();
      int? submittedSeq;
      String? submittedWatermark;
      api.readWork = (seq, watermark) {
        submittedSeq = seq;
        submittedWatermark = watermark;
        return read.future;
      };
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadNotifications();
      final marking = repo.markNotificationsRead(readAll: true);
      await Future<void>.delayed(Duration.zero);
      api.notificationWork = (_) async => MomentsPageResult(
          items: [notification('new', seq: 101), notification('n', seq: 100)],
          unreadCount: 2,
          readThroughSeq: 101,
          seenWatermark: 'watermark-101');
      await repo.loadNotifications();
      read.complete(1);
      await marking;
      expect(submittedSeq, 100);
      expect(submittedWatermark, 'watermark-100');
      expect(repo.notifications.singleWhere((item) => item.seq == 101).read,
          false);
      expect(
          repo.notifications.singleWhere((item) => item.seq == 100).read, true);
      expect(repo.unreadCount, 1);
    });
    test('older history page never lowers the first-page seen watermark',
        () async {
      final api = FakeMomentsApi()
        ..notificationWork = (cursor) async => cursor == null
            ? MomentsPageResult(
                items: [notification('new')],
                hasMore: true,
                nextCursor: 'older',
                readThroughSeq: 100,
                seenWatermark: 'watermark-100')
            : MomentsPageResult(
                items: [notification('old', seq: 50)],
                readThroughSeq: 50,
                seenWatermark: 'watermark-50');
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadNotifications();
      await repo.loadNotifications(refresh: false);
      expect(repo.readThroughSeq, 100);
      expect(repo.seenWatermark, 'watermark-100');
    });
    test('nonadvancing cursor is a protocol error, not an infinite load loop',
        () async {
      final api = FakeMomentsApi()
        ..feedWork = (_) async => MomentsPageResult(
            items: [post('post')], hasMore: true, nextCursor: 'same');
      final repo = repository(api);
      addTearDown(repo.dispose);
      await repo.loadFeed();
      await expectLater(repo.loadFeed(refresh: false), throwsFormatException);
      expect(api.feedCalls, 2);
      expect(repo.feedState.error, isA<FormatException>());
    });
  });
}
