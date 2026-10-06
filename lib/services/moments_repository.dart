import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import '../core/controller/im_controller.dart';
import '../core/im_callback.dart';
import '../pages/moments/privacy/data/moments_privacy_selection_controller.dart';
import 'moments_api.dart';
export 'moments_api.dart';
export '../pages/moments/privacy/data/moments_privacy_selection_store.dart';
export '../pages/moments/privacy/data/moments_privacy_selections.dart';

class MomentsQueryState {
  List<MomentPost> items = const [];
  String? nextCursor;
  bool hasMore = false;
  bool loading = false;
  Object? error;
  MomentUser? author;
  String? coverUrl;
  int? visibleRangeDays;
  String viewerContextVersion = '';
  int _generation = 0;
  bool _restartRequired = true;
}

class MomentsCommentQueryState {
  List<MomentComment> items = const [];
  String? nextCursor;
  bool hasMore = false;
  bool loading = false;
  Object? error;
  String viewerContextVersion = '';
  int _generation = 0;
  bool _restartRequired = true;
}

/// Account-scoped live entities, pagination and defensive privacy projections.
/// This never replaces the server's friendship authority or resource ACL.
class MomentsRepository extends ChangeNotifier with WidgetsBindingObserver {
  MomentsRepository(
      {MomentsApi? api,
      String Function()? userIdProvider,
      String Function()? environmentProvider,
      Future<List<MomentUser>> Function()? friendLoader,
      MomentsPrivacySelectionStore? privacySelectionStore,
      this.subscribeToSdk = true})
      : api = api ?? MomentsApi(),
        _userIdProvider = userIdProvider ?? (() => DataSp.userID ?? ''),
        _environmentProvider = environmentProvider,
        _friendLoader = friendLoader,
        _privacySelections =
            MomentsPrivacySelectionController(store: privacySelectionStore),
        _checkCredentials = userIdProvider == null {
    if (subscribeToSdk) WidgetsBinding.instance.addObserver(this);
  }
  static final MomentsRepository instance = MomentsRepository();
  final MomentsApi api;
  final String Function() _userIdProvider;
  final String Function()? _environmentProvider;
  final Future<List<MomentUser>> Function()? _friendLoader;
  final MomentsPrivacySelectionController _privacySelections;
  final bool subscribeToSdk;
  final bool _checkCredentials;
  bool _disposed = false;
  String _identity = '';
  String? _credential;
  int _sessionGeneration = 0;
  int _permissionGeneration = 0;
  MomentsCapabilities? capabilities;
  MomentsSettings? settings;
  final Map<String, MomentPost> _posts = {};
  final Map<String, int> _tombstones = {};
  final MomentsQueryState feedState = MomentsQueryState();
  final Map<String, MomentsQueryState> _users = {};
  final Map<String, MomentsCommentQueryState> _comments = {};
  final Set<String> _detailIds = {};
  final Map<String, int> _detailPins = {};
  List<MomentUser>? _friends;
  Object? friendshipError;
  Future<List<MomentUser>>? _friendsWork;
  int _friendGeneration = 0;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _relationTimer;
  final Set<String> _seenEvents = {};
  Future<MomentsCapabilities>? _capabilitiesWork;
  List<MomentNotification> _notifications = const [];
  bool notificationsLoading = false;
  Object? notificationsError;
  bool notificationsHasMore = false;
  String? _notificationCursor;
  String _notificationContextVersion = '';
  int _notificationGeneration = 0;
  bool _notificationRestartRequired = true;
  int _unreadCount = 0;
  bool notificationsCountsTrusted = true;
  String? seenWatermark;
  int? readThroughSeq;

  String get currentUserId => _userIdProvider();
  String get baseUrl => _environmentProvider?.call() ?? api.baseUrl;
  String get sessionScope => _ensureSession();
  String get authorizationScope => '$sessionScope|$_permissionGeneration';
  bool isSessionCurrent(String scope) =>
      !_disposed && _ensureSession() == scope;
  bool get available => capabilities?.enabled == true;

  /// Confirmed changes made on this device, never a server ACL snapshot.
  MomentsPrivacySelections get privacySelections {
    _ensureSession();
    return _privacySelections.value;
  }

  bool get privacySelectionsLoaded {
    _ensureSession();
    return _privacySelections.loaded;
  }

  Object? get privacyPersistenceError {
    _ensureSession();
    return _privacySelections.persistenceError;
  }

  Map<String, MomentPost> get postsById => Map.unmodifiable(_posts);
  MomentPost? postById(String id) => _posts[id];
  List<MomentUser> get friends => List.unmodifiable(_friends ?? const []);
  List<MomentNotification> get notifications => _notifications;
  int get unreadCount => notificationsCountsTrusted ? _unreadCount : 0;
  MomentsQueryState userState(String userId) =>
      _users.putIfAbsent(userId, MomentsQueryState.new);
  MomentsCommentQueryState commentState(String momentId) =>
      _comments.putIfAbsent(momentId, MomentsCommentQueryState.new);
  Map<String, String> get mediaHeaders => api.mediaHeaders;
  String mediaUrl(MomentMedia media, {bool thumbnail = false}) =>
      api.mediaUrl(thumbnail && media.thumbPath.isNotEmpty
          ? media.thumbPath
          : media.contentPath.isNotEmpty
              ? media.contentPath
              : '/moments/media/${Uri.encodeComponent(media.mediaId)}/content${thumbnail ? '?variant=thumb' : ''}');
  Future<Uint8List> downloadMedia(MomentMedia media,
      {bool thumbnail = false}) async {
    final scope = _ensureSession();
    final permission = _permissionGeneration;
    final bytes =
        await _protect(() => api.downloadMedia(media, thumbnail: thumbnail));
    _guard(scope, permission);
    return bytes;
  }

  String _ensureSession() {
    final identity = '$baseUrl|$currentUserId';
    final credential = _checkCredentials ? DataSp.chatToken : null;
    if (identity != _identity || credential != _credential) {
      _identity = identity;
      _credential = credential;
      _sessionGeneration++;
      _relationTimer?.cancel();
      _seenEvents.clear();
      _clearPrivateState();
      _detailIds.clear();
      _detailPins.clear();
      _users.clear();
      _comments.clear();
      _capabilitiesWork = null;
      _friendsWork = null;
      capabilities = null;
      settings = null;
      _privacySelections.reset();
    }
    return '$identity|$_sessionGeneration';
  }

  void _guard(String scope, [int? permission]) {
    if (!isSessionCurrent(scope)) {
      throw const MomentsException('登录状态已变化',
          code: 'SESSION_CHANGED', authRequired: true);
    }
    if (permission != null && permission != _permissionGeneration) {
      throw const MomentsException('权限上下文已变化，请刷新',
          code: 'CONTEXT_CHANGED', permissionDenied: true);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearQuery(MomentsQueryState state) {
    state.items = const [];
    state.nextCursor = null;
    state.hasMore = false;
    state.loading = false;
    state.error = null;
    state.author = null;
    state.coverUrl = null;
    state.visibleRangeDays = null;
    state.viewerContextVersion = '';
    state._restartRequired = true;
    state._generation++;
  }

  void _clearPrivateState() {
    _permissionGeneration++;
    _friendGeneration++;
    _friends = null;
    _friendsWork = null;
    friendshipError = null;
    _posts.clear();
    _tombstones.clear();
    _clearQuery(feedState);
    for (final state in _users.values) {
      _clearQuery(state);
    }
    for (final state in _comments.values) {
      state.items = const [];
      state.loading = false;
      state.error = null;
      state.hasMore = false;
      state.nextCursor = null;
      state.viewerContextVersion = '';
      state._restartRequired = true;
      state._generation++;
    }
    _notificationGeneration++;
    _notifications = const [];
    notificationsLoading = false;
    notificationsError = null;
    notificationsHasMore = false;
    _notificationCursor = null;
    _notificationContextVersion = '';
    _notificationRestartRequired = true;
    _unreadCount = 0;
    notificationsCountsTrusted = true;
    seenWatermark = null;
    readThroughSeq = null;
  }

  void resetSession() {
    _identity = '';
    _ensureSession();
    _notify();
  }

  Future<MomentsCapabilities> ensureCapabilities({bool force = false}) async {
    final scope = _ensureSession();
    if (currentUserId.isEmpty) {
      throw const MomentsException('请重新登录',
          authRequired: true, code: 'AUTH_REQUIRED');
    }
    if (!force && capabilities?.enabled == true) {
      return capabilities!;
    }
    final work = !force && _capabilitiesWork != null
        ? _capabilitiesWork!
        : api.capabilities();
    _capabilitiesWork = work;
    try {
      final value = await work;
      _guard(scope);
      capabilities = value;
      if (!value.enabled) {
        _clearPrivateState();
        throw const MomentsException('朋友圈服务尚未开放',
            code: 'UNAVAILABLE', unavailable: true);
      }
      _notify();
      return value;
    } on MomentsException catch (error) {
      if (isSessionCurrent(scope) && error.unavailable) {
        capabilities = const MomentsCapabilities();
        _clearPrivateState();
        _notify();
      }
      rethrow;
    } finally {
      if (identical(_capabilitiesWork, work)) _capabilitiesWork = null;
    }
  }

  Future<void> _requireFeature(String feature) async {
    final caps = await ensureCapabilities();
    final enabled = switch (feature) {
      'read' => caps.readEnabled,
      'publish' => caps.publishEnabled,
      'settings' => caps.settingsEnabled,
      'interact' => caps.interactionsEnabled,
      _ => false
    };
    if (!enabled) throw const MomentsException('该朋友圈功能尚未开放', unavailable: true);
  }

  void _connectSdk() {
    if (!subscribeToSdk ||
        _subscriptions.isNotEmpty ||
        !Get.isRegistered<IMController>()) {
      return;
    }
    final controller = Get.find<IMController>();
    _subscriptions.add(controller.friendAddSubject.stream
        .skip(controller.friendAddSubject.hasValue ? 1 : 0)
        .listen((_) => _relationChanged()));
    _subscriptions.add(controller.friendDelSubject.stream
        .skip(controller.friendDelSubject.hasValue ? 1 : 0)
        .listen((_) => _relationChanged()));
    _subscriptions.add(
        controller.friendInfoChangedSubject.listen((_) => _relationChanged()));
    _subscriptions.add(
        controller.blacklistChangedSubject.listen((_) => _relationChanged()));
    _subscriptions
        .add(controller.onKickedOfflineSubject.listen((_) => resetSession()));
    _subscriptions.add(controller.imSdkStatusPublishSubject.listen((event) {
      if (event.status == IMSdkStatus.syncEnded) _relationChanged();
    }));
    _subscriptions.add(controller.customBusinessMessageSubject.listen((raw) {
      try {
        final envelope = jsonDecode(raw);
        if (envelope is! Map || envelope['key'] != 'moments') return;
        _ensureSession();
        dynamic data = envelope['data'];
        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (_) {
            data = null;
          }
        }
        final eventId = data is Map ? data['eventId'] : null;
        if (eventId is String && eventId.isNotEmpty) {
          if (!_seenEvents.add(eventId)) return;
          if (_seenEvents.length > 256) _seenEvents.remove(_seenEvents.first);
        }
        // Only the key and event ID are trusted here. Payloads are never posts,
        // and aggregateVersion has no confirmed relation to post.version.
        _relationChanged();
      } catch (_) {
        /* Other business event types are handled by their owners. */
      }
    }));
  }

  void _relationChanged({List<MomentUser>? verifiedFriends}) {
    if (_disposed) return;
    final scope = _ensureSession();
    final albums = _users.keys.toList();
    final details = _detailIds.toList();
    _clearPrivateState();
    if (verifiedFriends != null) {
      _friends = List.unmodifiable(verifiedFriends);
      friendshipError = null;
    }
    _friendsWork = null;
    _notify();
    _relationTimer?.cancel();
    _relationTimer = Timer(const Duration(milliseconds: 200), () async {
      if (!isSessionCurrent(scope) || !available) return;
      try {
        await _reloadQueries(albums, details);
      } catch (_) {
        /* Keep invalidated content hidden until an explicit retry. */
      }
    });
  }

  Future<List<MomentUser>> loadFriends({bool force = false}) async {
    final scope = _ensureSession();
    _connectSdk();
    if (!force && _friends != null) return friends;
    if (!force && _friendsWork != null) return _friendsWork!;
    final generation = ++_friendGeneration;
    final work = _friendLoader != null ? _friendLoader() : _sdkFriends();
    _friendsWork = work;
    try {
      final result = await work;
      _guard(scope);
      if (generation != _friendGeneration) {
        throw const MomentsException('好友关系已变化，请刷新', code: 'CONTEXT_CHANGED');
      }
      final unique = <String, MomentUser>{
        for (final friend in result)
          if (friend.userId.isNotEmpty && friend.userId != currentUserId)
            friend.userId: friend
      };
      final previousIds = _friends?.map((friend) => friend.userId).toSet();
      _friends = List.unmodifiable(unique.values);
      if (previousIds != null &&
          previousIds.any((id) => !unique.containsKey(id))) {
        // A confirmed removal is a revocation even when it arrives before
        // the SDK event. Invalidate old text, media and in-flight responses.
        _relationChanged(verifiedFriends: _friends);
        return friends;
      }
      if (previousIds != null &&
          (previousIds.length != unique.length ||
              !previousIds.containsAll(unique.keys))) {
        // A forced picker refresh can learn a relation change before the SDK
        // broadcast. Reproject existing interactions in one notification.
        _applyPosts(_posts.values.toList());
        for (final state in _comments.values) {
          state.items = List.unmodifiable(state.items.where(commentVisible));
        }
        final notifications =
            _notifications.where(_notificationVisible).toList(growable: false);
        if (notifications.length != _notifications.length) {
          notificationsCountsTrusted = false;
        }
        _notifications = List.unmodifiable(notifications);
      }
      friendshipError = null;
      _notify();
      return friends;
    } catch (error) {
      if (isSessionCurrent(scope) && generation == _friendGeneration) {
        friendshipError = error;
      }
      rethrow;
    } finally {
      if (identical(_friendsWork, work)) _friendsWork = null;
    }
  }

  Future<List<MomentUser>> _sdkFriends() async {
    final result = <MomentUser>[];
    var offset = 0;
    const size = 1000;
    for (var pageNumber = 0; pageNumber < 1000; pageNumber++) {
      final page = await OpenIM.iMManager.friendshipManager
          .getFriendListPage(offset: offset, count: size, filterBlack: true);
      for (final friend in page) {
        final id = friend.userID;
        if (id != null && id.isNotEmpty) {
          result.add(MomentUser(
              userId: id,
              nickname: friend.nickname ?? '',
              avatarUrl: friend.faceURL ?? '',
              remark: friend.remark ?? ''));
        }
      }
      if (page.length < size) return result;
      offset += page.length;
    }
    throw const MomentsException('好友列表过大，请稍后重试');
  }

  Future<void> _prepareRead({bool requireFriendship = false}) async {
    await _requireFeature('read');
    try {
      await loadFriends();
    } catch (_) {
      /* Unknown friendship never grants display of third-party interactions. */
    }
    if (requireFriendship && _friends == null) {
      throw const MomentsException('暂时无法确认好友关系，请稍后重试',
          code: 'FRIENDSHIP_UNAVAILABLE');
    }
  }

  bool _actorVisible(MomentUser actor) =>
      actor.userId.isNotEmpty &&
      (actor.userId == currentUserId ||
          (_friends?.any((friend) => friend.userId == actor.userId) ?? false));
  bool commentVisible(MomentComment comment) =>
      _actorVisible(comment.author) &&
      (comment.replyToCommentId == null ||
          comment.replyToUser != null && _actorVisible(comment.replyToUser!));
  MomentPost _filterPost(MomentPost post) {
    final likes = post.likesPreview
        .where((like) => _actorVisible(like.user))
        .toList(growable: false);
    final comments =
        post.commentsPreview.where(commentVisible).toList(growable: false);
    final trusted = _friends != null &&
        likes.length == post.likesPreview.length &&
        comments.length == post.commentsPreview.length &&
        post.likeCount >= likes.length &&
        post.commentCount >= comments.length &&
        (post.likeCount == 0 || likes.isNotEmpty) &&
        (post.commentCount == 0 || comments.isNotEmpty) &&
        post.interactionCountsTrusted;
    return post.copyWith(
        likesPreview: List.unmodifiable(likes),
        commentsPreview: List.unmodifiable(comments),
        audienceUserIds: post.author.userId == currentUserId
            ? post.audienceUserIds
            : const [],
        interactionCountsTrusted: trusted);
  }

  void applyPost(MomentPost value) {
    if (_applyPosts([value])) _notify();
  }

  /// A page is a single state transition. Existing albums are projected once,
  /// and the loading query is assembled once by its pagination owner.
  bool _applyPosts(Iterable<MomentPost> values,
      {MomentsQueryState? loadingQuery}) {
    _ensureSession();
    if (_disposed) return false;
    final changed = <String, MomentPost>{};
    for (final value in values) {
      final post = _filterPost(value);
      if ((_tombstones[post.momentId] ?? -1) >= post.version) continue;
      final old = _posts[post.momentId];
      if (old != null && old.version > post.version) continue;
      _posts[post.momentId] = post;
      changed[post.momentId] = post;
    }
    if (changed.isEmpty) return false;
    for (final state in [feedState, ..._users.values]) {
      if (identical(state, loadingQuery) ||
          !state.items.any((item) => changed.containsKey(item.momentId))) {
        continue;
      }
      state.items = List.unmodifiable(
          state.items.map((item) => changed[item.momentId] ?? item));
    }
    return true;
  }

  Future<MomentsPageResult<MomentPost>> loadFeed({bool refresh = true}) =>
      _loadPosts(feedState, refresh, (cursor) => api.feed(cursor: cursor));
  Future<MomentsPageResult<MomentPost>> loadUser(String userId,
      {bool refresh = true}) {
    _ensureSession();
    return _loadPosts(userState(userId), refresh,
        (cursor) => api.userMoments(userId, cursor: cursor));
  }

  Future<MomentsPageResult<MomentPost>> _loadPosts(
      MomentsQueryState state,
      bool refresh,
      Future<MomentsPageResult<MomentPost>> Function(String?) fetch,
      {bool allowContextRetry = true}) async {
    final scope = _ensureSession();
    final permission = _permissionGeneration;
    if (state.loading && !refresh) return _snapshot(state);
    refresh = refresh || state._restartRequired;
    if (!refresh && !state.hasMore) {
      return _snapshot(state);
    }
    final generation = ++state._generation;
    state.loading = true;
    state.error = null;
    _notify();
    final cursor = refresh ? null : state.nextCursor;
    try {
      await _prepareRead();
      _guard(scope, permission);
      final page = await fetch(cursor);
      _guard(scope, permission);
      if (generation != state._generation) return _snapshot(state);
      _validatePageContext(
          refresh, state.viewerContextVersion, page.viewerContextVersion);
      if (page.hasMore && page.nextCursor == cursor) {
        throw const FormatException('Moments cursor did not advance');
      }
      _applyPosts(page.items, loadingQuery: state);
      final ids = <String>{
        if (!refresh) ...state.items.map((post) => post.momentId),
        ...page.items.map((post) => post.momentId)
      };
      state.items = List.unmodifiable(
          ids.map((id) => _posts[id]).whereType<MomentPost>());
      state.nextCursor = page.nextCursor;
      state.hasMore = page.hasMore;
      state.author = page.author;
      state.coverUrl = page.coverUrl;
      state.visibleRangeDays = page.visibleRangeDays;
      state.viewerContextVersion = page.viewerContextVersion;
      state._restartRequired = false;
      return _snapshot(state);
    } catch (error) {
      if (isSessionCurrent(scope) && generation == state._generation) {
        state.error = error;
        _handlePrivacyError(error);
        if (allowContextRetry && _paginationInvalid(error)) {
          return _loadPosts(state, true, fetch, allowContextRetry: false);
        }
      }
      rethrow;
    } finally {
      if (isSessionCurrent(scope) && generation == state._generation) {
        state.loading = false;
        _notify();
      }
    }
  }

  MomentsPageResult<MomentPost> _snapshot(MomentsQueryState state) =>
      MomentsPageResult(
          items: state.items,
          nextCursor: state.nextCursor,
          hasMore: state.hasMore,
          author: state.author,
          coverUrl: state.coverUrl,
          visibleRangeDays: state.visibleRangeDays,
          viewerContextVersion: state.viewerContextVersion);
  Future<MomentPost> loadDetail(String momentId,
      {bool trackForSync = true}) async {
    final scope = _ensureSession();
    final permission = _permissionGeneration;
    try {
      await _prepareRead();
      _guard(scope, permission);
      final post = await api.detail(momentId);
      _guard(scope, permission);
      if (post.momentId != momentId) {
        throw const FormatException('Unexpected moments ID');
      }
      applyPost(post);
      if (trackForSync) _detailIds.add(momentId);
      return _posts[momentId] ?? _filterPost(post);
    } catch (error) {
      if (isSessionCurrent(scope) && permission == _permissionGeneration) {
        _handlePrivacyError(error);
      }
      rethrow;
    }
  }

  void retainDetail(String momentId) {
    _ensureSession();
    _detailPins[momentId] = (_detailPins[momentId] ?? 0) + 1;
    _detailIds.add(momentId);
  }

  void releaseDetail(String momentId, {String? sessionScope}) {
    if (sessionScope != null && !isSessionCurrent(sessionScope)) return;
    final remaining = (_detailPins[momentId] ?? 1) - 1;
    if (remaining > 0) {
      _detailPins[momentId] = remaining;
    } else {
      _detailPins.remove(momentId);
      _detailIds.remove(momentId);
    }
  }

  Future<MomentsPageResult<MomentLike>> loadLikes(String momentId,
          {String? cursor}) =>
      _loadLikes(momentId, cursor: cursor);
  Future<MomentsPageResult<MomentLike>> _loadLikes(String momentId,
      {String? cursor, bool allowContextRetry = true}) async {
    final scope = _ensureSession();
    final permission = _permissionGeneration;
    try {
      await _prepareRead(requireFriendship: true);
      _guard(scope, permission);
      final page = await api.likes(momentId, cursor: cursor);
      _guard(scope, permission);
      if (page.hasMore &&
          (page.nextCursor == null ||
              page.nextCursor!.isEmpty ||
              page.nextCursor == cursor)) {
        throw const FormatException('Moments cursor did not advance');
      }
      final visible = page.items
          .where((like) => _actorVisible(like.user))
          .toList(growable: false);
      if (visible.length != page.items.length && _posts.containsKey(momentId)) {
        applyPost(_posts[momentId]!.copyWith(interactionCountsTrusted: false));
      }
      return MomentsPageResult(
          items: List.unmodifiable(visible),
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          viewerContextVersion: page.viewerContextVersion);
    } catch (error) {
      if (isSessionCurrent(scope) && permission == _permissionGeneration) {
        _handlePrivacyError(error);
        if (allowContextRetry && _paginationInvalid(error)) {
          return _loadLikes(momentId, allowContextRetry: false);
        }
      }
      rethrow;
    }
  }

  Future<MomentsPageResult<MomentComment>> loadComments(String momentId,
          {bool refresh = true}) =>
      _loadComments(momentId, refresh: refresh);
  Future<MomentsPageResult<MomentComment>> _loadComments(String momentId,
      {bool refresh = true, bool allowContextRetry = true}) async {
    final scope = _ensureSession();
    final permission = _permissionGeneration;
    final state = commentState(momentId);
    if (state.loading && !refresh) {
      return MomentsPageResult(
          items: state.items,
          nextCursor: state.nextCursor,
          hasMore: state.hasMore,
          viewerContextVersion: state.viewerContextVersion);
    }
    refresh = refresh || state._restartRequired;
    if (!refresh && !state.hasMore) {
      return MomentsPageResult(
          items: state.items,
          nextCursor: state.nextCursor,
          hasMore: state.hasMore);
    }
    final generation = ++state._generation;
    final cursor = refresh ? null : state.nextCursor;
    state.loading = true;
    state.error = null;
    _notify();
    try {
      await _prepareRead(requireFriendship: true);
      _guard(scope, permission);
      final page = await api.comments(momentId, cursor: cursor);
      _guard(scope, permission);
      if (generation != state._generation) {
        return MomentsPageResult(items: state.items);
      }
      _validatePageContext(
          refresh, state.viewerContextVersion, page.viewerContextVersion);
      if (page.hasMore && page.nextCursor == cursor) {
        throw const FormatException('Moments cursor did not advance');
      }
      final visible = page.items.where(commentVisible).toList();
      final all = <String, MomentComment>{
        if (!refresh)
          for (final comment in state.items) comment.commentId: comment,
        for (final comment in visible) comment.commentId: comment
      };
      state.items = List.unmodifiable(all.values);
      state.nextCursor = page.nextCursor;
      state.hasMore = page.hasMore;
      state.viewerContextVersion = page.viewerContextVersion;
      state._restartRequired = false;
      if (visible.length != page.items.length && _posts.containsKey(momentId)) {
        applyPost(_posts[momentId]!.copyWith(interactionCountsTrusted: false));
      }
      return MomentsPageResult(
          items: state.items,
          nextCursor: state.nextCursor,
          hasMore: state.hasMore,
          viewerContextVersion: state.viewerContextVersion);
    } catch (error) {
      if (isSessionCurrent(scope) && generation == state._generation) {
        state.error = error;
        _handlePrivacyError(error);
        if (allowContextRetry && _paginationInvalid(error)) {
          return _loadComments(momentId, allowContextRetry: false);
        }
      }
      rethrow;
    } finally {
      if (isSessionCurrent(scope) && generation == state._generation) {
        state.loading = false;
        _notify();
      }
    }
  }

  bool _paginationInvalid(Object error) =>
      error is MomentsException &&
      (error.code == 'CONTEXT_CHANGED' || error.code == 'CURSOR_EXPIRED');

  void _validatePageContext(bool refresh, String previous, String next) {
    if (!refresh &&
        previous.isNotEmpty &&
        next.isNotEmpty &&
        previous != next) {
      throw const MomentsException('权限上下文已变化，请刷新', code: 'CONTEXT_CHANGED');
    }
  }

  void _handlePrivacyError(Object error) {
    if (error is MomentsException &&
        (error.permissionDenied ||
            error.authRequired ||
            error.unavailable ||
            error.code == 'RELATION_UNAVAILABLE' ||
            _paginationInvalid(error))) {
      _clearPrivateState();
      for (final state in [feedState, ..._users.values]) {
        state.error = error;
      }
      for (final state in _comments.values) {
        state.error = error;
      }
      notificationsError = error;
      _notify();
    }
  }

  Future<T> _protect<T>(Future<T> Function() work) async {
    final scope = _ensureSession();
    final permission = _permissionGeneration;
    try {
      final result = await work();
      _guard(scope);
      return result;
    } catch (error) {
      if (isSessionCurrent(scope) && permission == _permissionGeneration) {
        _handlePrivacyError(error);
      }
      rethrow;
    }
  }

  Future<MomentPost?> setLiked(String momentId, bool liked) async {
    final scope = _ensureSession();
    // Self-cleanup stays available even when reading or new interactions stop.
    if (liked) await _requireFeature('interact');
    _guard(scope);
    await _protect(() => api.setLiked(momentId, liked));
    _guard(scope);
    final previous = _posts[momentId];
    if (previous != null) {
      applyPost(previous.copyWith(
          likedByMe: liked,
          likesPreview: liked
              ? previous.likesPreview
              : previous.likesPreview
                  .where((like) => like.user.userId != currentUserId)
                  .toList(),
          interactionCountsTrusted: false));
    }
    try {
      return await loadDetail(momentId, trackForSync: false);
    } catch (_) {
      _guard(scope);
      // A confirmed mutation remains successful if its parent cannot be read.
      return null;
    }
  }

  Future<MomentComment> addComment(String momentId,
      {required String text,
      String? clientRequestId,
      String? replyToCommentId}) async {
    final scope = _ensureSession();
    await _requireFeature('interact');
    _guard(scope);
    final comment = await _protect(() => api.createComment(momentId,
        text: text,
        clientRequestId: clientRequestId ?? const Uuid().v4(),
        replyToCommentId: replyToCommentId));
    _guard(scope);
    if (commentVisible(comment)) {
      final state = commentState(momentId);
      ++state._generation;
      state.loading = false;
      state.error = null;
      final all = <String, MomentComment>{
        for (final item in state.items) item.commentId: item,
        comment.commentId: comment
      };
      final ordered = all.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state.items = List.unmodifiable(ordered);
      _notify();
    }
    try {
      await loadDetail(momentId, trackForSync: false);
    } catch (_) {
      /* A confirmed comment is not converted into a failed send by a follow-up read. */
    }
    _guard(scope);
    return comment;
  }

  Future<void> deleteComment(String momentId, String commentId) async {
    final scope = _ensureSession();
    await _protect(() => api.deleteComment(momentId, commentId));
    _guard(scope);
    final state = _comments[momentId];
    if (state != null) {
      ++state._generation;
      state.loading = false;
      state.error = null;
      state.items = List.unmodifiable(
          state.items.where((item) => item.commentId != commentId));
    }
    final previous = _posts[momentId];
    if (previous != null) {
      applyPost(previous.copyWith(
          commentsPreview: previous.commentsPreview
              .where((comment) => comment.commentId != commentId)
              .toList(),
          interactionCountsTrusted: false));
    }
    _notify();
    try {
      await loadDetail(momentId, trackForSync: false);
    } catch (_) {
      /* A confirmed self-cleanup does not require access to the parent. */
    }
    _guard(scope);
  }

  Future<void> deletePost(String momentId) async {
    final scope = _ensureSession();
    await _protect(() => api.deletePost(momentId));
    _guard(scope);
    _tombstones[momentId] = (_posts[momentId]?.version ?? 0) + 1;
    _posts.remove(momentId);
    for (final state in [feedState, ..._users.values]) {
      state.items = List.unmodifiable(
          state.items.where((post) => post.momentId != momentId));
    }
    _comments.remove(momentId);
    _notifications = List.unmodifiable(
        _notifications.where((item) => item.momentId != momentId));
    _notify();
  }

  Future<MomentPost> updateVisibility(String momentId,
      {required String visibility,
      List<String> audienceUserIds = const [],
      required int expectedVersion}) async {
    final scope = _ensureSession();
    final post = await _protect(() => api.updateVisibility(momentId,
        visibility: visibility,
        audienceUserIds: audienceUserIds,
        expectedVersion: expectedVersion));
    _guard(scope);
    applyPost(post);
    return _posts[post.momentId] ?? post;
  }

  Future<void> reportPost(String momentId,
      {required String reason, String? commentId}) async {
    final scope = _ensureSession();
    await _protect(
        () => api.reportPost(momentId, reason: reason, commentId: commentId));
    _guard(scope);
  }

  bool _notificationVisible(MomentNotification item) =>
      item.available &&
      _actorVisible(item.actor) &&
      (item.comment == null || commentVisible(item.comment!)) &&
      (item.replyToUser == null || _actorVisible(item.replyToUser!));
  Future<MomentsPageResult<MomentNotification>> loadNotifications(
          {bool refresh = true}) =>
      _loadNotifications(refresh: refresh);
  Future<MomentsPageResult<MomentNotification>> _loadNotifications(
      {bool refresh = true, bool allowContextRetry = true}) async {
    final scope = _ensureSession();
    final permission = _permissionGeneration;
    if (notificationsLoading && !refresh) {
      return MomentsPageResult(
          items: _notifications,
          nextCursor: _notificationCursor,
          hasMore: notificationsHasMore,
          viewerContextVersion: _notificationContextVersion);
    }
    refresh = refresh || _notificationRestartRequired;
    if (!refresh && !notificationsHasMore) {
      return MomentsPageResult(
          items: _notifications,
          nextCursor: _notificationCursor,
          hasMore: notificationsHasMore);
    }
    final generation = ++_notificationGeneration;
    final cursor = refresh ? null : _notificationCursor;
    notificationsLoading = true;
    notificationsError = null;
    _notify();
    try {
      await _prepareRead(requireFriendship: true);
      _guard(scope, permission);
      final page = await api.notifications(cursor: cursor);
      _guard(scope, permission);
      if (generation != _notificationGeneration) {
        return MomentsPageResult(items: _notifications);
      }
      _validatePageContext(
          refresh, _notificationContextVersion, page.viewerContextVersion);
      if (page.hasMore && page.nextCursor == cursor) {
        throw const FormatException('Moments cursor did not advance');
      }
      final visible = page.items.where(_notificationVisible).toList();
      notificationsCountsTrusted = _friends != null &&
          visible.length == page.items.where((item) => item.available).length &&
          (refresh || notificationsCountsTrusted);
      final all = <String, MomentNotification>{
        if (!refresh)
          for (final item in _notifications) item.notificationId: item,
        for (final item in visible) item.notificationId: item
      };
      _notifications = List.unmodifiable(all.values);
      _notificationCursor = page.nextCursor;
      _notificationContextVersion = page.viewerContextVersion;
      notificationsHasMore = page.hasMore;
      _notificationRestartRequired = false;
      _unreadCount = page.unreadCount;
      // Paging older history cannot replace the first page's observed high-water mark.
      if (refresh) {
        seenWatermark = page.seenWatermark;
        readThroughSeq = page.readThroughSeq;
      }
      return MomentsPageResult(
          items: _notifications,
          nextCursor: _notificationCursor,
          hasMore: notificationsHasMore,
          seenWatermark: seenWatermark,
          readThroughSeq: readThroughSeq,
          unreadCount: unreadCount,
          viewerContextVersion: _notificationContextVersion);
    } catch (error) {
      if (isSessionCurrent(scope) && generation == _notificationGeneration) {
        notificationsError = error;
        _handlePrivacyError(error);
        if (allowContextRetry && _paginationInvalid(error)) {
          return _loadNotifications(allowContextRetry: false);
        }
      }
      rethrow;
    } finally {
      if (isSessionCurrent(scope) && generation == _notificationGeneration) {
        notificationsLoading = false;
        _notify();
      }
    }
  }

  Future<void> markNotificationsRead(
      {List<String> notificationIds = const [], bool readAll = false}) async {
    final scope = _ensureSession();
    final watermark = seenWatermark;
    final through = readThroughSeq;
    if (readAll && (watermark == null || through == null)) {
      throw const MomentsException('请刷新消息列表后再标记已读');
    }
    final knownIds = _notifications.map((item) => item.notificationId).toSet();
    final remaining = await _protect(() => api.markNotificationsRead(
        notificationIds: readAll ? const [] : notificationIds,
        readThroughSeq: readAll ? through : null,
        seenWatermark: readAll ? watermark : null));
    _guard(scope);
    _unreadCount = remaining;
    _notifications = List.unmodifiable(_notifications.map((item) => (readAll
            ? item.seq != null
                ? item.seq! <= through!
                : knownIds.contains(item.notificationId)
            : notificationIds.contains(item.notificationId))
        ? item.asRead()
        : item));
    _notify();
  }

  Future<MomentsSettings> loadSettings() async {
    final scope = _ensureSession();
    await _requireFeature('settings');
    _guard(scope);
    final value = await _protect(api.settings);
    _guard(scope);
    settings = value;
    _notify();
    return value;
  }

  Future<MomentsSettings> updateSettings(
      {int? visibleRangeDays,
      String? coverMediaId,
      bool clearCover = false,
      int? expectedVersion}) async {
    final scope = _ensureSession();
    await _requireFeature('settings');
    _guard(scope);
    final previous = settings ?? await loadSettings();
    _guard(scope);
    final value = await _protect(() => api.updateSettings(
        visibleRangeDays: visibleRangeDays,
        coverMediaId: coverMediaId,
        clearCover: clearCover,
        expectedVersion: expectedVersion ?? previous.version));
    _guard(scope);
    settings = value;
    _clearPrivateState();
    _notify();
    return value;
  }

  Future<MomentsPrivacySelections> loadPrivacySelections(
      {bool force = false}) async {
    final scope = _ensureSession();
    final owner = currentUserId;
    final server = baseUrl;
    if (owner.isEmpty) {
      throw const MomentsException('请重新登录', authRequired: true);
    }
    final value = await _privacySelections.load(
        ownerUserId: owner, baseUrl: server, force: force);
    _guard(scope);
    _notify();
    return value;
  }

  Future<void> retryPrivacyPersistence() async {
    final scope = _ensureSession();
    await _privacySelections.persistPending(
        ownerUserId: currentUserId, baseUrl: baseUrl);
    _guard(scope);
    _notify();
  }

  Future<MomentsSettings> _setPrivacyEntry(
      MomentsPrivacySelectionKind kind, String userId, bool enabled) async {
    final scope = _ensureSession();
    final owner = currentUserId;
    final server = baseUrl;
    await _requireFeature('settings');
    _guard(scope);
    await loadPrivacySelections();
    _guard(scope);
    // The response is an operation acknowledgement. It cannot restore either
    // list and must not overwrite the cover, visible range or settings version.
    await _protect(() => kind == MomentsPrivacySelectionKind.blockedViewer
        ? api.setBlockedViewer(userId, enabled)
        : api.setHiddenAuthor(userId, enabled));
    _guard(scope);
    final confirmation = _privacySelections.confirm(
        ownerUserId: owner,
        baseUrl: server,
        change:
            MomentsPrivacyChange(kind: kind, userId: userId, enabled: enabled));
    // A confirmed policy change invalidates every previously readable query.
    // Local disk latency must not delay permission invalidation or refreshing
    // through the existing SDK lifecycle, which coalesces successive changes.
    _relationChanged();
    await confirmation;
    _guard(scope);
    _notify();
    return settings ?? const MomentsSettings();
  }

  Future<MomentsSettings> setBlockedViewer(String userId, bool blocked) =>
      _setPrivacyEntry(
          MomentsPrivacySelectionKind.blockedViewer, userId, blocked);

  Future<MomentsSettings> setHiddenAuthor(String userId, bool hidden) =>
      _setPrivacyEntry(
          MomentsPrivacySelectionKind.hiddenAuthor, userId, hidden);

  Future<void> refreshAuthorization() async {
    _ensureSession();
    final albums = _users.keys.toList();
    final details = _detailIds.toList();
    _clearPrivateState();
    _friendsWork = null;
    _notify();
    await _reloadQueries(albums, details);
  }

  Future<void> _reloadQueries(List<String> albums, List<String> details) async {
    final scope = _ensureSession();
    final permission = _permissionGeneration;
    try {
      await loadFriends(force: true);
    } catch (_) {
      /* Each query reports its own retryable state; unrelated reads continue. */
    }
    _guard(scope, permission);
    final work = <Future<dynamic>>[
      loadFeed(),
      for (final id in albums) loadUser(id),
      for (final id in details)
        if (_detailIds.contains(id)) loadDetail(id, trackForSync: false),
      for (final id in details)
        if (_detailIds.contains(id)) loadComments(id),
      loadNotifications(),
    ];
    await Future.wait(work.map((future) =>
        future.then<void>((_) {}, onError: (Object _, StackTrace __) {})));
    _guard(scope);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && available) {
      unawaited(refreshAuthorization().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _relationTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    if (subscribeToSdk) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
