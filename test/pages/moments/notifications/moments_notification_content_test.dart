import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim/pages/moments/notifications/data/moments_notification_content.dart';

const actor = MomentUser(userId: 'friend');
const notification = MomentNotification(
    notificationId: 'n',
    actor: actor,
    momentId: 'p',
    type: 'COMMENT',
    commentId: 'c',
    seq: 8);
const media =
    MomentMedia(mediaId: 'photo', thumbPath: '/moments/media/photo/thumb');
const comment = MomentComment(commentId: 'c', author: actor, text: '好漂亮');

class Api extends MomentsApi {
  int details = 0;
  int commentCalls = 0;
  Object? failure;
  Completer<MomentPost>? gate;
  @override
  Future<MomentsCapabilities> capabilities() async =>
      const MomentsCapabilities(enabled: true, readEnabled: true);
  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
          {String? cursor, int pageSize = 20}) async =>
      const MomentsPageResult(items: [notification], unreadCount: 1);
  @override
  Future<int> markNotificationsRead(
          {List<String> notificationIds = const [],
          int? readThroughSeq,
          String? seenWatermark}) async =>
      0;
  @override
  Future<MomentPost> detail(String id) async {
    details++;
    if (failure != null) throw failure!;
    return gate == null
        ? MomentPost(
            momentId: id, author: actor, text: '周末出游', mediaList: const [media])
        : gate!.future;
  }

  @override
  Future<MomentsPageResult<MomentComment>> comments(String id,
      {String? cursor, int pageSize = 20}) async {
    commentCalls++;
    return const MomentsPageResult(items: [comment]);
  }
}

void main() {
  test(
      'inbox lease enriches live refreshes and release restores lightweight reads',
      () async {
    final api = Api();
    final repository = MomentsRepository(
        api: api,
        userIdProvider: () => 'me',
        environmentProvider: () => 'test',
        friendLoader: () async => [actor],
        subscribeToSdk: false);
    addTearDown(repository.dispose);
    final release = repository.retainNotificationContent();
    await repository.loadNotifications();
    await Future<void>.delayed(Duration.zero);
    expect(repository.notifications.single.comment!.text, '好漂亮');
    release();
    release();
    final calls = api.details;
    await repository.loadNotifications();
    expect(api.details, calls);
  });
  test('detail author visibility is checked before using post content',
      () async {
    final api = Api();
    final result = await MomentsNotificationContent.load(
        items: [notification],
        api: api,
        isCurrent: () => true,
        canReadPost: (_) => false);
    expect(result.single.available, isFalse);
    expect(api.commentCalls, 0);
  });
  test(
      'friend directory resolves ID-only actor and avatar with remark priority',
      () {
    final result = MomentsNotificationContent.withFriend(notification, {
      'friend': const MomentUser(
          userId: 'friend', nickname: '小林', remark: '林同学', avatarUrl: 'avatar')
    });
    expect(result.actor.displayName, '林同学');
    expect(result.actor.avatarUrl, 'avatar');
    expect(result.notificationId, 'n');
  });
  test('known preview payload and read acknowledgement preserve thumbnail', () {
    final item = MomentNotification.fromJson({
      'notificationID': 'n',
      'actor': {'userID': 'friend'},
      'momentPreviewMedia': {
        'type': 'VIDEO',
        'thumbUrl': '/moments/thumb',
        'url': '/moments/video'
      }
    });
    expect(item.previewMedia!.isVideo, isTrue);
    expect(item.asRead().previewMedia!.thumbPath, '/moments/thumb');
  });
  test('same post is fetched once and comment body is matched by ID', () async {
    final api = Api();
    final result = await MomentsNotificationContent.load(
        items: [notification, notification], api: api, isCurrent: () => true);
    expect(api.details, 1);
    expect(api.commentCalls, 1);
    expect(result.first.comment!.text, '好漂亮');
    expect(result.first.momentText, '周末出游');
    expect(result.first.previewMedia, media);
  });
  test('network failure preserves inbox; forbidden content becomes unavailable',
      () async {
    final api = Api()..failure = const MomentsException('offline');
    var result = await MomentsNotificationContent.load(
        items: [notification], api: api, isCurrent: () => true);
    expect(result.single, notification);
    api.failure = const MomentsException('denied', permissionDenied: true);
    result = await MomentsNotificationContent.load(
        items: [notification], api: api, isCurrent: () => true);
    expect(result.single.available, isFalse);
  });
  test(
      'background refresh does not fetch details; enrichment preserves newer read state',
      () async {
    final api = Api()..gate = Completer<MomentPost>();
    final repository = MomentsRepository(
        api: api,
        userIdProvider: () => 'me',
        environmentProvider: () => 'test',
        friendLoader: () async => [actor],
        subscribeToSdk: false);
    addTearDown(repository.dispose);
    await repository.loadNotifications();
    expect(api.details, 0);
    await repository.loadNotifications(includeContent: true);
    await repository.markNotificationsRead(notificationIds: ['n']);
    api.gate!.complete(const MomentPost(
        momentId: 'p',
        author: actor,
        text: '补全内容',
        commentsPreview: [comment],
        mediaList: [media]));
    await Future<void>.delayed(Duration.zero);
    expect(repository.notifications.single.read, isTrue);
    expect(repository.notifications.single.momentText, '补全内容');
  });
  test('late enrichment cannot populate a different account', () async {
    final api = Api()..gate = Completer<MomentPost>();
    var user = 'me';
    final repository = MomentsRepository(
        api: api,
        userIdProvider: () => user,
        environmentProvider: () => 'test',
        friendLoader: () async => [actor],
        subscribeToSdk: false);
    addTearDown(repository.dispose);
    await repository.loadNotifications(includeContent: true);
    user = 'new-account';
    repository.sessionScope;
    api.gate!.complete(
        const MomentPost(momentId: 'p', author: actor, text: '旧账号内容'));
    await Future<void>.delayed(Duration.zero);
    expect(repository.notifications, isEmpty);
  });
}
