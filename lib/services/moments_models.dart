/// Business API models. No local sample content is used by the feature.
library;

class MomentsException implements Exception {
  const MomentsException(
    this.message, {
    this.code = '',
    this.statusCode,
    this.unavailable = false,
    this.permissionDenied = false,
    this.authRequired = false,
    this.unknownResult = false,
    this.relationUnavailable = false,
  });
  final String message;
  final String code;
  final int? statusCode;
  final bool unavailable;
  final bool permissionDenied;
  final bool authRequired;
  final bool unknownResult;
  final bool relationUnavailable;
  @override
  String toString() => message;
}

String momentsErrorMessage(Object error) {
  if (error is MomentsException) {
    if (error.relationUnavailable) return '暂时无法确认好友关系，请稍后重试';
    if (error.unavailable) return '朋友圈服务尚未开放，请稍后再试';
    if (error.authRequired) return '登录状态已变化，请重新登录后继续';
    if (error.permissionDenied) return '内容已不可用或无权查看';
    if (error.unknownResult) return '结果尚未确认，请保留当前任务并重试确认';
    return error.message;
  }
  if (error is FormatException) return '数据格式不符合朋友圈协议，请稍后再试';
  return '加载失败，请检查网络后重试';
}

Map<String, dynamic> momentsMap(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid moments object');
  return Map<String, dynamic>.from(value);
}

String _string(dynamic value, [String fallback = '']) =>
    value is String ? value : fallback;
String? _optionalId(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;
int _int(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;
int? _optionalInt(dynamic value) => value is num ? value.toInt() : null;
List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) parse) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('Invalid moments list');
  return List<T>.unmodifiable(value.map((item) => parse(momentsMap(item))));
}

List<String> _ids(dynamic value) => value is List
    ? List<String>.unmodifiable(
        value.whereType<String>().where((id) => id.isNotEmpty).toSet())
    : const [];
List<String> _settingsIds(dynamic value) {
  if (value == null) return const [];
  if (value is! List ||
      value
          .any((id) => id is! String || id.trim().isEmpty || id != id.trim())) {
    throw const FormatException('Invalid moments privacy list');
  }
  return List<String>.unmodifiable(value.cast<String>().toSet());
}

String _requiredId(dynamic value) {
  final id = _string(value);
  if (id.trim().isEmpty) throw const FormatException('Missing moments ID');
  return id;
}

MomentUser? _replyUser(dynamic value, {required bool deleted}) {
  if (value == null) return null;
  final json = momentsMap(value);
  // Keep only the authorised ID, never old identifying fields, for tombstones.
  return deleted
      ? MomentUser(userId: _requiredId(json['userID'] ?? json['userId']))
      : MomentUser.fromJson(json);
}

class MomentUser {
  const MomentUser(
      {required this.userId,
      this.nickname = '',
      this.avatarUrl = '',
      this.remark = ''});
  final String userId;
  final String nickname;
  final String avatarUrl;
  final String remark;
  String get displayName => remark.trim().isNotEmpty
      ? remark
      : nickname.trim().isNotEmpty
          ? nickname
          : userId;
  factory MomentUser.fromJson(Map<String, dynamic> json) => MomentUser(
        userId: _requiredId(json['userID'] ?? json['userId']),
        nickname: _string(json['nickname']),
        avatarUrl:
            _string(json['avatarURL'] ?? json['avatarUrl'] ?? json['faceURL']),
        remark: _string(json['remark']),
      );
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'nickname': nickname,
        'avatarUrl': avatarUrl,
        'remark': remark
      };
}

class MomentMedia {
  const MomentMedia(
      {required this.mediaId,
      this.type = 'IMAGE',
      this.contentPath = '',
      this.thumbPath = '',
      this.width,
      this.height,
      this.durationSec,
      this.sizeBytes,
      this.status = 'READY'});
  final String mediaId;
  final String type;
  final String contentPath;
  final String thumbPath;
  final int? width;
  final int? height;
  final int? durationSec;
  final int? sizeBytes;
  final String status;
  bool get isVideo => type == 'VIDEO';
  bool get isReady => status == 'READY';
  factory MomentMedia.fromJson(Map<String, dynamic> json) => MomentMedia(
        mediaId: _requiredId(json['mediaID'] ??
            json['mediaId'] ??
            json['coverMediaID'] ??
            json['coverMediaId']),
        type: _string(json['type']).isEmpty ? 'IMAGE' : _string(json['type']),
        contentPath: _string(json['contentPath']),
        thumbPath: _string(json['thumbPath']),
        width: _optionalInt(json['width']),
        height: _optionalInt(json['height']),
        durationSec: _optionalInt(json['durationSec']),
        sizeBytes: _optionalInt(json['sizeBytes']),
        status:
            _string(json['status']).isEmpty ? 'READY' : _string(json['status']),
      );
  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        'type': type,
        'contentPath': contentPath,
        'thumbPath': thumbPath,
        'width': width,
        'height': height,
        'durationSec': durationSec,
        'sizeBytes': sizeBytes,
        'status': status
      };
}

class MomentLike {
  const MomentLike({required this.user, this.createdAt = 0});
  final MomentUser user;
  final int createdAt;
  factory MomentLike.fromJson(Map<String, dynamic> json) => MomentLike(
      user: MomentUser.fromJson(momentsMap(json['actor'] ?? json['user'])),
      createdAt: _int(json['createdAt']));
  Map<String, dynamic> toJson() =>
      {'user': user.toJson(), 'createdAt': createdAt};
}

class MomentComment {
  const MomentComment(
      {required this.commentId,
      required this.author,
      this.text = '',
      this.replyToCommentId,
      MomentUser? replyToUser,
      this.rootCommentId,
      this.createdAt = 0,
      this.canDelete = false,
      this.replyTargetDeleted = false})
      : _replyToUser = replyToUser;
  final String commentId;
  final MomentUser author;
  final String text;
  final String? replyToCommentId;
  final MomentUser? _replyToUser;

  /// A deleted target carries only its authorised ID for friendship checks.
  MomentUser? get replyToUser => replyTargetDeleted && _replyToUser != null
      ? MomentUser(userId: _replyToUser.userId)
      : _replyToUser;
  String get replyTargetLabel =>
      replyTargetDeleted ? '已删除评论' : replyToUser?.displayName ?? '';
  final String? rootCommentId;
  final int createdAt;
  final bool canDelete;
  final bool replyTargetDeleted;
  factory MomentComment.fromJson(Map<String, dynamic> json) => MomentComment(
        commentId: _requiredId(json['commentID'] ?? json['commentId']),
        author:
            MomentUser.fromJson(momentsMap(json['actor'] ?? json['author'])),
        text: _string(json['text']),
        replyToCommentId:
            _optionalId(json['replyToCommentID'] ?? json['replyToCommentId']),
        replyToUser: _replyUser(json['replyTo'] ?? json['replyToUser'],
            deleted:
                (json['replyToDeleted'] ?? json['replyTargetDeleted']) == true),
        rootCommentId:
            _optionalId(json['rootCommentID'] ?? json['rootCommentId']),
        createdAt: _int(json['createdAt']),
        canDelete: json['canDelete'] == true,
        replyTargetDeleted:
            (json['replyToDeleted'] ?? json['replyTargetDeleted']) == true,
      );
  Map<String, dynamic> toJson() => {
        'commentId': commentId,
        'author': author.toJson(),
        'text': text,
        'replyToCommentId': replyToCommentId,
        'replyToUser': replyToUser?.toJson(),
        'rootCommentId': rootCommentId,
        'createdAt': createdAt,
        'canDelete': canDelete,
        'replyTargetDeleted': replyTargetDeleted
      };
}

class MomentPost {
  const MomentPost(
      {required this.momentId,
      required this.author,
      this.text = '',
      this.mediaList = const [],
      this.likesPreview = const [],
      this.commentsPreview = const [],
      this.likeCount = 0,
      this.commentCount = 0,
      this.likedByMe = false,
      this.createdAt = 0,
      this.visibility = 'FRIENDS',
      this.audienceUserIds = const [],
      this.version = 0,
      this.viewerContextVersion = '',
      this.authorSettingsVersion = 0,
      this.status = 'PUBLISHED',
      this.canLike = false,
      this.canComment = false,
      this.canDelete = false,
      this.canEditVisibility = false,
      this.interactionCountsTrusted = true});
  final String momentId;
  final MomentUser author;
  final String text;
  final List<MomentMedia> mediaList;
  final List<MomentLike> likesPreview;
  final List<MomentComment> commentsPreview;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final int createdAt;
  int get publishedAt => createdAt;
  final String visibility;
  final List<String> audienceUserIds;
  final int version;
  final String viewerContextVersion;
  final int authorSettingsVersion;
  final String status;
  final bool canLike;
  final bool canComment;
  final bool canDelete;
  final bool canEditVisibility;

  /// False after client defence removed entries. Never display raw totals then.
  final bool interactionCountsTrusted;
  factory MomentPost.fromJson(Map<String, dynamic> json) => MomentPost(
        momentId: _requiredId(json['momentID'] ?? json['momentId']),
        author: MomentUser.fromJson(momentsMap(json['author'])),
        text: _string(json['text']),
        mediaList: _list(json['mediaList'], MomentMedia.fromJson),
        likesPreview:
            _list(json['likesPreview'] ?? json['likes'], MomentLike.fromJson),
        commentsPreview: _list(json['commentsPreview'] ?? json['comments'],
            MomentComment.fromJson),
        likeCount: _int(json['likeCount']),
        commentCount: _int(json['commentCount']),
        likedByMe: json['likedByMe'] == true,
        createdAt: _int(json['publishedAt'] ?? json['createdAt']),
        visibility: _string(json['visibility'], 'FRIENDS'),
        audienceUserIds: _ids(json['audienceUserIds']),
        version: _int(json['version']),
        viewerContextVersion: _string(json['viewerContextVersion']),
        authorSettingsVersion: _int(json['authorSettingsVersion']),
        status: _string(json['status'], 'PUBLISHED'),
        canLike: json['canLike'] == true,
        canComment: json['canComment'] == true,
        canDelete: json['canDelete'] == true,
        canEditVisibility: json['canEditVisibility'] == true,
      );
  MomentPost copyWith(
          {List<MomentLike>? likesPreview,
          List<MomentComment>? commentsPreview,
          int? likeCount,
          int? commentCount,
          bool? likedByMe,
          List<String>? audienceUserIds,
          bool? interactionCountsTrusted}) =>
      MomentPost(
        momentId: momentId,
        author: author,
        text: text,
        mediaList: mediaList,
        likesPreview: likesPreview ?? this.likesPreview,
        commentsPreview: commentsPreview ?? this.commentsPreview,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        likedByMe: likedByMe ?? this.likedByMe,
        createdAt: createdAt,
        visibility: visibility,
        audienceUserIds: audienceUserIds ?? this.audienceUserIds,
        version: version,
        viewerContextVersion: viewerContextVersion,
        authorSettingsVersion: authorSettingsVersion,
        status: status,
        canLike: canLike,
        canComment: canComment,
        canDelete: canDelete,
        canEditVisibility: canEditVisibility,
        interactionCountsTrusted:
            interactionCountsTrusted ?? this.interactionCountsTrusted,
      );
  Map<String, dynamic> toJson() => {
        'momentId': momentId,
        'author': author.toJson(),
        'text': text,
        'mediaList': mediaList.map((item) => item.toJson()).toList(),
        'likesPreview': likesPreview.map((item) => item.toJson()).toList(),
        'commentsPreview':
            commentsPreview.map((item) => item.toJson()).toList(),
        'likeCount': likeCount,
        'commentCount': commentCount,
        'likedByMe': likedByMe,
        'publishedAt': createdAt,
        'visibility': visibility,
        'audienceUserIds': audienceUserIds,
        'version': version,
        'viewerContextVersion': viewerContextVersion,
        'authorSettingsVersion': authorSettingsVersion,
        'status': status,
        'canLike': canLike,
        'canComment': canComment,
        'canDelete': canDelete,
        'canEditVisibility': canEditVisibility
      };
}

class MomentsPageResult<T> {
  const MomentsPageResult(
      {required this.items,
      this.nextCursor,
      this.hasMore = false,
      this.seenWatermark,
      this.readThroughSeq,
      this.author,
      this.coverUrl,
      this.visibleRangeDays,
      this.unreadCount = 0,
      this.viewerContextVersion = ''});
  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
  final String? seenWatermark;
  final int? readThroughSeq;
  final MomentUser? author;
  final String? coverUrl;
  final int? visibleRangeDays;
  final int unreadCount;
  final String viewerContextVersion;
  factory MomentsPageResult.fromJson(
      Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    if (!json.containsKey('items') ||
        json['items'] != null && json['items'] is! List) {
      throw const FormatException('Missing moments page');
    }
    final more = json['hasMore'] == true;
    final cursor = json['nextCursor'] as String?;
    if (more && (cursor == null || cursor.isEmpty)) {
      throw const FormatException('Missing moments continuation');
    }
    return MomentsPageResult<T>(
        items: _list(json['items'], parse),
        nextCursor: cursor,
        hasMore: more,
        seenWatermark: json['seenWatermark'] as String?,
        readThroughSeq: _optionalInt(json['lastSeq'] ?? json['readThroughSeq']),
        author: json['user'] == null && json['author'] == null
            ? null
            : MomentUser.fromJson(momentsMap(json['user'] ?? json['author'])),
        coverUrl: (json['coverPath'] ?? json['coverUrl']) as String?,
        visibleRangeDays: _optionalInt(json['visibleRangeDays']),
        unreadCount: _int(json['unreadCount']),
        viewerContextVersion: _string(json['viewerContextVersion']));
  }
}

class MomentsCapabilities {
  const MomentsCapabilities(
      {bool? supportsMoments,
      bool enabled = false,
      this.readEnabled = false,
      this.publishEnabled = false,
      this.interactionsEnabled = false,
      this.videoEnabled = false,
      this.reportsEnabled = false,
      this.settingsEnabled = false,
      this.maxImages = 9,
      this.maxTextLength = 2000,
      this.maxCommentLength = 500,
      this.maxImageBytes = 10485760,
      this.protocolVersion = 1})
      : supportsMoments = supportsMoments ?? enabled;
  final bool supportsMoments;
  bool get enabled => supportsMoments;
  final bool readEnabled,
      publishEnabled,
      interactionsEnabled,
      videoEnabled,
      reportsEnabled,
      settingsEnabled;
  final int maxImages,
      maxTextLength,
      maxCommentLength,
      maxImageBytes,
      protocolVersion;
  factory MomentsCapabilities.fromJson(Map<String, dynamic> json) {
    final supported = json['supportsMoments'] == true;
    return MomentsCapabilities(
        supportsMoments: supported,
        readEnabled: supported,
        publishEnabled: supported,
        interactionsEnabled: supported,
        videoEnabled: false,
        reportsEnabled: false,
        settingsEnabled: supported,
        maxImages: _int(json['maxImages'], 9),
        maxTextLength: _int(json['maxTextLength'], 2000),
        maxCommentLength: _int(json['maxCommentLength'], 500),
        maxImageBytes: _int(json['maxImageBytes'], 10485760),
        protocolVersion:
            json['protocolVersion'] is int ? json['protocolVersion'] : 0);
  }
}

class MomentsSettings {
  const MomentsSettings(
      {this.coverUrl,
      this.coverMediaId,
      this.visibleRangeDays = 0,
      this.blockedViewerIds = const [],
      this.hiddenAuthorIds = const [],
      this.blockedViewersLoaded = true,
      this.hiddenAuthorsLoaded = true,
      this.version = 0,
      this.viewerContextVersion = ''});
  final String? coverUrl, coverMediaId;
  final String viewerContextVersion;
  final int visibleRangeDays, version;
  final List<String> blockedViewerIds, hiddenAuthorIds;

  /// Missing means unknown; an explicit null means a known empty list.
  final bool blockedViewersLoaded, hiddenAuthorsLoaded;
  factory MomentsSettings.fromJson(Map<String, dynamic> json) =>
      MomentsSettings(
          coverUrl: (json['coverPath'] ?? json['coverUrl']) as String?,
          coverMediaId:
              (json['coverMediaID'] ?? json['coverMediaId']) as String?,
          visibleRangeDays: _int(json['visibleRangeDays']),
          blockedViewerIds: _settingsIds(json.containsKey('blockedViewerIDs')
              ? json['blockedViewerIDs']
              : json['blockedViewerIds']),
          hiddenAuthorIds: _settingsIds(json.containsKey('hiddenAuthorIDs')
              ? json['hiddenAuthorIDs']
              : json['hiddenAuthorIds']),
          blockedViewersLoaded: json.containsKey('blockedViewerIDs') ||
              json.containsKey('blockedViewerIds'),
          hiddenAuthorsLoaded: json.containsKey('hiddenAuthorIDs') ||
              json.containsKey('hiddenAuthorIds'),
          version: _int(json['version']),
          viewerContextVersion: _string(json['viewerContextVersion']));
}

class MomentNotification {
  const MomentNotification(
      {required this.notificationId,
      required this.actor,
      this.type = '',
      this.momentId = '',
      this.commentId = '',
      this.momentText = '',
      this.comment,
      MomentUser? replyToUser,
      this.createdAt = 0,
      this.read = false,
      this.available = true,
      this.seq})
      : _replyToUser = replyToUser;
  final String notificationId, type, momentId, commentId, momentText;
  final MomentUser actor;
  final MomentComment? comment;
  final MomentUser? _replyToUser;
  MomentUser? get replyToUser =>
      comment?.replyTargetDeleted == true && _replyToUser != null
          ? MomentUser(userId: _replyToUser.userId)
          : _replyToUser;
  final int createdAt;
  final int? seq;
  final bool read, available;
  factory MomentNotification.fromJson(Map<String, dynamic> json) =>
      MomentNotification(
        notificationId:
            _requiredId(json['notificationID'] ?? json['notificationId']),
        actor: json['actor'] == null
            ? const MomentUser(userId: '')
            : MomentUser.fromJson(momentsMap(json['actor'])),
        type: _string(json['type']).toUpperCase(),
        momentId: _string(json['momentID'] ?? json['momentId']),
        commentId: _string(json['commentID'] ?? json['commentId']),
        momentText: _string(json['momentText']),
        comment: json['comment'] == null
            ? null
            : MomentComment.fromJson(momentsMap(json['comment'])),
        replyToUser: _replyUser(json['replyToUser'],
            deleted: json['comment'] is Map &&
                (json['comment']['replyToDeleted'] ??
                        json['comment']['replyTargetDeleted']) ==
                    true),
        createdAt: _int(json['createdAt']),
        seq: _optionalInt(json['seq']),
        read: json['unread'] is bool
            ? json['unread'] == false
            : json['read'] == true || json['readAt'] != null,
        available: json['available'] != false && json['unavailable'] != true,
      );
  MomentNotification asRead() => MomentNotification(
      notificationId: notificationId,
      actor: actor,
      type: type,
      momentId: momentId,
      commentId: commentId,
      momentText: momentText,
      comment: comment,
      replyToUser: replyToUser,
      createdAt: createdAt,
      read: true,
      available: available,
      seq: seq);
}

class MomentsWriteResult {
  const MomentsWriteResult(
      {required this.status,
      this.resourceId,
      this.post,
      this.comment,
      this.message = ''});
  final String status;
  final String? resourceId;
  final MomentPost? post;
  final MomentComment? comment;
  final String message;
  bool get succeeded => status == 'SUCCEEDED' || status == 'COMMITTED';
  bool get rejected => status == 'REJECTED';
  bool get notFound => status == 'NOT_FOUND';
  bool get processing => status == 'PROCESSING' || status == 'UNKNOWN';
  factory MomentsWriteResult.fromJson(Map<String, dynamic> json) =>
      MomentsWriteResult(
          status: _string(json['status'], 'UNKNOWN'),
          resourceId: json['resourceID'] as String? ??
              json['resourceId'] as String? ??
              json['momentID'] as String? ??
              json['momentId'] as String? ??
              json['commentID'] as String? ??
              json['commentId'] as String?,
          post: json['post'] == null && json['moment'] == null
              ? null
              : MomentPost.fromJson(momentsMap(json['post'] ?? json['moment'])),
          comment: json['comment'] == null
              ? null
              : MomentComment.fromJson(momentsMap(json['comment'])),
          message: _string(json['message']));
}
