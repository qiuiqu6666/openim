import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:openim/services/moments_repository.dart';

import '../privacy/privacy_test_store.dart';

const momentsUiSelf = MomentUser(userId: 'preview-self', nickname: '阿南');
const momentsUiFriend = MomentUser(userId: 'preview-friend', nickname: '小林');
const momentsUiSecondFriend =
    MomentUser(userId: 'preview-second-friend', nickname: '阿雯');
const momentsUiServer = 'https://moments-preview.example';
const momentsUiFriendPostId = 'preview-friend-post';
const momentsUiOwnPostId = 'preview-own-post';

const momentsUiPhotos = [
  MomentMedia(
      mediaId: 'preview-scenery',
      contentPath: '/preview/scenery',
      thumbPath: '/preview/scenery-thumb',
      width: 576,
      height: 1024),
  MomentMedia(
      mediaId: 'preview-car',
      contentPath: '/preview/car',
      thumbPath: '/preview/car-thumb',
      width: 576,
      height: 1024),
  MomentMedia(
      mediaId: 'preview-cover',
      contentPath: '/preview/cover',
      thumbPath: '/preview/cover-thumb',
      width: 1024,
      height: 768),
];

const momentsUiComments = [
  MomentComment(
      commentId: 'preview-comment-one',
      author: momentsUiSecondFriend,
      text: '每一张都很好看，周末一起去吧！',
      createdAt: 1791000600000),
  MomentComment(
      commentId: 'preview-comment-two',
      author: momentsUiFriend,
      text: '好呀，下次一起出发。',
      replyToCommentId: 'preview-comment-one',
      replyToUser: momentsUiSecondFriend,
      createdAt: 1791000660000),
];

/// Samples live exclusively in tests and pass through the real repository.
List<MomentPost> momentsUiPosts() => [
      MomentPost(
          momentId: momentsUiFriendPostId,
          author: momentsUiFriend,
          text: '慢下来，发现生活里的小美好。\n周末和朋友出发，沿途都是风景。',
          mediaList: momentsUiPhotos,
          likesPreview: const [
            MomentLike(user: momentsUiSelf),
            MomentLike(user: momentsUiSecondFriend),
          ],
          commentsPreview: momentsUiComments,
          likeCount: 2,
          commentCount: 2,
          likedByMe: true,
          createdAt: DateTime(2026, 10, 3, 9, 30).millisecondsSinceEpoch,
          version: 1,
          canLike: true,
          canComment: true),
      MomentPost(
          momentId: momentsUiOwnPostId,
          author: momentsUiSelf,
          text: '阳光刚好，心情也刚好。\n把这一刻留在相册里。',
          mediaList: [momentsUiPhotos.first, momentsUiPhotos.last],
          likesPreview: const [MomentLike(user: momentsUiFriend)],
          likeCount: 1,
          createdAt: DateTime(2026, 10, 3, 8, 20).millisecondsSinceEpoch,
          version: 1,
          canLike: true,
          canComment: true,
          canDelete: true,
          canEditVisibility: true),
      MomentPost(
          momentId: 'preview-own-same-day',
          author: momentsUiSelf,
          text: '路上的风，和远处的山。',
          mediaList: [momentsUiPhotos[1]],
          createdAt: DateTime(2026, 10, 3, 7, 10).millisecondsSinceEpoch,
          version: 1,
          canLike: true,
          canComment: true,
          canDelete: true,
          canEditVisibility: true),
      MomentPost(
          momentId: 'preview-own-previous-day',
          author: momentsUiSelf,
          text: '认真生活，记住普通日子里的快乐。',
          createdAt: DateTime(2026, 10, 2, 17, 45).millisecondsSinceEpoch,
          version: 1,
          canLike: true,
          canComment: true,
          canDelete: true,
          canEditVisibility: true),
    ];

class MomentsUiFixture {
  MomentsUiFixture({List<MomentPost>? posts})
      : api = MomentsUiApi(posts: posts ?? momentsUiPosts()) {
    repository = MomentsRepository(
        api: api,
        userIdProvider: () => ownerUserId,
        environmentProvider: () => server,
        friendLoader: () async =>
            const [momentsUiFriend, momentsUiSecondFriend],
        privacySelectionStore: MemoryPrivacySelectionStore(
            ownerUserId: momentsUiSelf.userId, baseUrl: momentsUiServer),
        subscribeToSdk: false);
  }

  final MomentsUiApi api;
  late final MomentsRepository repository;
  String ownerUserId = momentsUiSelf.userId;
  String server = momentsUiServer;

  /// Loads existing package photos; never performs HTTP or creates UI samples.
  Future<void> loadPhotos() async {
    const paths = {
      'preview-scenery':
          'packages/openim_common/assets/images/chat_backgrounds/scenery.png',
      'preview-car':
          'packages/openim_common/assets/images/chat_backgrounds/car.png',
      'preview-cover':
          'packages/openim_common/assets/images/moments_cover_99chat.webp',
    };
    for (final entry in paths.entries) {
      final data = await rootBundle.load(entry.value);
      api.mediaBytes[entry.key] = data.buffer.asUint8List();
    }
  }

  void dispose() => repository.dispose();
}

/// Fake transport only. Layout, entity filtering and mutation flows are real.
class MomentsUiApi extends MomentsApi {
  MomentsUiApi({required List<MomentPost> posts})
      : posts = {for (final post in posts) post.momentId: post},
        super(baseUrl: momentsUiServer, client: _offlineClient()) {
    for (final post in posts) {
      commentItems[post.momentId] = List.of(post.commentsPreview);
    }
  }

  static Dio _offlineClient() => Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.reject(DioException(
          requestOptions: request,
          type: DioExceptionType.cancel,
          error: StateError('Implement this operation in the test transport')));
    }));

  final Map<String, MomentPost> posts;
  final Map<String, List<MomentComment>> commentItems = {};
  final Map<String, Uint8List> mediaBytes = {};
  final feedCursors = <String?>[];
  final albumRequests = <String>[];
  final detailRequests = <String>[];
  final commentRequests = <String?>[];
  final mediaRequests = <String>[];
  final likeWrites = <Map<String, Object>>[];
  final commentWrites = <Map<String, Object?>>[];
  int capabilityRequests = 0;
  int settingsRequests = 0;
  int notificationRequests = 0;
  Future<MomentsCapabilities> Function()? capabilitiesWork;
  Future<MomentsPageResult<MomentPost>> Function(String?)? feedWork;
  Future<MomentsPageResult<MomentPost>> Function(String, String?)? albumWork;
  Future<MomentPost> Function(String)? detailWork;
  Future<MomentsPageResult<MomentComment>> Function(String, String?)?
      commentsWork;
  Future<MomentsSettings> Function()? settingsWork;
  Future<MomentsPageResult<MomentNotification>> Function()? notificationsWork;
  Future<Uint8List> Function(MomentMedia, bool)? mediaWork;

  @override
  Future<MomentsCapabilities> capabilities() async {
    ++capabilityRequests;
    return capabilitiesWork?.call() ??
        MomentsCapabilities.fromJson({'supportsMoments': true});
  }

  @override
  Future<MomentsPageResult<MomentPost>> feed(
      {String? cursor, int pageSize = 20}) async {
    feedCursors.add(cursor);
    return feedWork?.call(cursor) ??
        MomentsPageResult(items: posts.values.toList(), author: momentsUiSelf);
  }

  @override
  Future<MomentsPageResult<MomentPost>> userMoments(String userId,
      {String? cursor, int pageSize = 20}) async {
    albumRequests.add(userId);
    return albumWork?.call(userId, cursor) ??
        MomentsPageResult(
            items: posts.values
                .where((post) => post.author.userId == userId)
                .toList(),
            author: userId == momentsUiSelf.userId
                ? momentsUiSelf
                : momentsUiFriend,
            visibleRangeDays: 0);
  }

  @override
  Future<MomentPost> detail(String momentId) async {
    detailRequests.add(momentId);
    return detailWork?.call(momentId) ?? posts[momentId]!;
  }

  @override
  Future<MomentsPageResult<MomentComment>> comments(String momentId,
      {String? cursor, int pageSize = 20}) async {
    commentRequests.add(cursor);
    return commentsWork?.call(momentId, cursor) ??
        MomentsPageResult(items: List.of(commentItems[momentId] ?? const []));
  }

  @override
  Future<MomentsPageResult<MomentLike>> likes(String momentId,
          {String? cursor, int pageSize = 20}) async =>
      MomentsPageResult(items: posts[momentId]!.likesPreview);

  @override
  Future<void> setLiked(String momentId, bool liked) async {
    likeWrites.add({'momentId': momentId, 'liked': liked});
    final post = posts[momentId]!;
    final likes = post.likesPreview
        .where((like) => like.user.userId != momentsUiSelf.userId)
        .toList();
    if (liked) likes.add(const MomentLike(user: momentsUiSelf));
    posts[momentId] = _updated(post,
        likedByMe: liked, likeCount: likes.length, likesPreview: likes);
  }

  @override
  Future<MomentComment> createComment(String momentId,
      {required String text,
      required String clientRequestId,
      String? replyToCommentId}) async {
    commentWrites.add({
      'momentId': momentId,
      'text': text,
      'clientRequestId': clientRequestId,
      'replyToCommentId': replyToCommentId,
    });
    final comment = MomentComment(
        commentId: 'preview-written-${commentWrites.length}',
        author: momentsUiSelf,
        text: text,
        replyToCommentId: replyToCommentId,
        replyToUser: replyToCommentId == null
            ? null
            : commentItems[momentId]!
                .firstWhere((item) => item.commentId == replyToCommentId)
                .author,
        createdAt: DateTime(2026, 10, 3, 12).millisecondsSinceEpoch,
        canDelete: true);
    (commentItems[momentId] ??= []).add(comment);
    final post = posts[momentId]!;
    posts[momentId] = _updated(post,
        commentCount: commentItems[momentId]!.length,
        commentsPreview: commentItems[momentId]);
    return comment;
  }

  MomentPost _updated(MomentPost post,
          {bool? likedByMe,
          int? likeCount,
          int? commentCount,
          List<MomentLike>? likesPreview,
          List<MomentComment>? commentsPreview}) =>
      MomentPost.fromJson({
        ...post.toJson(),
        'version': post.version + 1,
        if (likedByMe != null) 'likedByMe': likedByMe,
        if (likeCount != null) 'likeCount': likeCount,
        if (commentCount != null) 'commentCount': commentCount,
        if (likesPreview != null)
          'likesPreview': likesPreview.map((like) => like.toJson()).toList(),
        if (commentsPreview != null)
          'commentsPreview':
              commentsPreview.map((comment) => comment.toJson()).toList(),
      });

  @override
  Future<Uint8List> downloadMedia(MomentMedia media,
      {bool thumbnail = false}) async {
    mediaRequests.add('${media.mediaId}:$thumbnail');
    if (mediaWork != null) return mediaWork!(media, thumbnail);
    final bytes = mediaBytes[media.mediaId];
    if (bytes == null) throw StateError('Load test package photos first');
    return bytes;
  }

  @override
  Future<MomentsSettings> settings() async {
    ++settingsRequests;
    return settingsWork?.call() ?? const MomentsSettings();
  }

  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
      {String? cursor, int pageSize = 20}) async {
    ++notificationRequests;
    return notificationsWork?.call() ??
        const MomentsPageResult(items: [
          MomentNotification(
              notificationId: 'preview-notification',
              actor: momentsUiFriend,
              momentId: momentsUiOwnPostId,
              type: 'LIKE',
              seq: 1)
        ], unreadCount: 1, readThroughSeq: 1, seenWatermark: 'preview-viewer');
  }
}
