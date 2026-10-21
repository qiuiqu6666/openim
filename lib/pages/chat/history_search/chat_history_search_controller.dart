import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'chat_history_search_source.dart';
import 'cloud/chat_history_cloud_sync.dart';
import 'cloud/chat_keyword_search_api.dart';
import 'cloud/search_sender_profiles.dart';

/// Owns one search page's state; dispose it with its page.
class ChatHistorySearchController extends ChangeNotifier {
  ChatHistorySearchController({
    required this.conversationID,
    ChatHistorySearchSource? source,
    ChatKeywordSearchApi? keywordApi,
    SearchSenderProfiles? senderProfiles,
    this.acceptResult,
  })  : _senderProfiles = senderProfiles ?? SearchSenderProfiles(),
        source = source ?? OpenIMChatHistorySearchSource(),
        _keywordApi =
            keywordApi ?? (source == null ? ChatKeywordSearchApi() : null);

  final ChatKeywordSearchApi? _keywordApi;
  final SearchSenderProfiles _senderProfiles;
  int _beforeSeq = 0, _snapshotSeq = 0;
  bool _keywordHasMore = true;
  bool get _usesKeywordApi =>
      _keywordApi != null &&
      ((_query.keyword.isEmpty &&
              (_query.senderIDs.isNotEmpty || _query.startDate != null)) ||
          (_query.keyword.isNotEmpty &&
              (_query.messageTypes.isEmpty ||
                  _query.messageTypes
                      .every(ChatKeywordSearchApi.contentTypes.contains))));

  static const pageSize = 30;
  final String conversationID;
  final ChatHistorySearchSource source;

  /// Presentation-specific exclusions run after raw SDK pagination. This keeps
  /// sparse categories (e.g. videos excluding animated stickers) fillable.
  final bool Function(Message)? acceptResult;
  final List<Message> _results = [];
  List<Message> _pending = [];
  ChatHistorySearchQuery _query = const ChatHistorySearchQuery();
  int _generation = 0;
  int _nextRawPage = 1;
  bool _rawHasMore = true;
  bool _loading = false;
  bool _failed = false;
  bool _hasSearched = false;
  bool _disposed = false;

  List<Message> get results => UnmodifiableListView(_results);

  void _sortMediaNewestFirst() {
    if (_query.messageTypes.isEmpty ||
        !_query.messageTypes.every((type) =>
            type == MessageType.picture || type == MessageType.video)) {
      return;
    }
    final originalOrder = {for (var i = 0; i < _results.length; i++) _results[i]: i};
    _results.sort((a, b) {
      final time = (b.sendTime ?? b.createTime ?? 0)
          .compareTo(a.sendTime ?? a.createTime ?? 0);
      if (time != 0) return time;
      final sequence = (b.seq ?? 0).compareTo(a.seq ?? 0);
      return sequence != 0
          ? sequence
          : originalOrder[a]!.compareTo(originalOrder[b]!);
    });
  }

  ChatHistorySearchQuery get query => _query;
  bool get loading => _loading;
  bool get failed => _failed;
  int? searchError;
  bool get invalidKeyword =>
      _usesKeywordApi &&
      _query.keyword.isNotEmpty &&
      (_query.keyword.runes.length < 2 || _query.keyword.runes.length > 64);
  bool get hasSearched => _hasSearched;
  bool get hasMore =>
      _hasSearched &&
      (_usesKeywordApi
          ? _keywordHasMore
          : (_pending.isNotEmpty ||
              _rawHasMore ||
              (source is ChatHistoryCloudSource &&
                  (source as ChatHistoryCloudSource).cloudHasMore)));

  /// Clearing the input also invalidates any in-flight keyword search.
  void removeMessage(String id) {
    if (_disposed) return;
    _results.removeWhere((message) => message.clientMsgID == id);
    _pending.removeWhere((message) => message.clientMsgID == id);
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    ++_generation;
    _query = const ChatHistorySearchQuery();
    _beforeSeq = _snapshotSeq = 0;
    _keywordHasMore = true;
    _results.clear();
    _pending = [];
    _nextRawPage = 1;
    _rawHasMore = true;
    _loading = false;
    _failed = false;
    searchError = null;
    _hasSearched = false;
    notifyListeners();
  }

  Future<void> search(ChatHistorySearchQuery query) async {
    if (_disposed) return;
    final snapshot = query.snapshot();
    ++_generation;
    _query = snapshot;
    _beforeSeq = _snapshotSeq = 0;
    _keywordHasMore = true;
    _results.clear();
    _pending = [];
    _nextRawPage = 1;
    _rawHasMore = true;
    _hasSearched = true;
    await _load();
  }

  Future<void> loadMore() async {
    if (_disposed || _loading || !hasMore) return;
    await _load(fillPage: true);
  }

  Future<void> retry() async {
    if (_disposed || _loading || !_failed) return;
    await _load(fillPage: true);
  }

  Future<void> _load({bool fillPage = false}) async {
    if (_usesKeywordApi) return _loadKeyword();
    final generation = _generation;
    final query = _query;
    var rawPage = _nextRawPage;
    var rawHasMore = _rawHasMore;
    final collected = List<Message>.of(_pending);
    final ids = <String>{
      for (final message in [..._results, ...collected])
        if (message.clientMsgID?.isNotEmpty == true) message.clientMsgID!,
    };
    _loading = true;
    _failed = false;
    notifyListeners();

    try {
      final cloud = source is ChatHistoryCloudSource
          ? source as ChatHistoryCloudSource
          : null;
      do {
        if (cloud != null &&
            cloud.cloudHasMore &&
            collected.length < pageSize &&
            (rawPage == 1 || !rawHasMore)) {
          await cloud.supplement(conversationID, () => _isCurrent(generation));
          if (!_isCurrent(generation)) return;
          // SDK hydration changes local offsets. Rescan and deduplicate instead
          // of applying an old offset to the newly populated database.
          rawPage = 1;
          rawHasMore = true;
        }
        var scanned = 0;
        while (collected.length < pageSize &&
            rawHasMore &&
            (cloud == null || scanned < 10)) {
          scanned++;
          final messages = await source.search(
            conversationID: conversationID,
            query: query,
            pageIndex: rawPage,
            count: pageSize,
          );
          if (!_isCurrent(generation)) return;
          ++rawPage;
          rawHasMore = messages.length >= pageSize;
          for (final message in messages) {
            if (!query.accepts(message) ||
                acceptResult?.call(message) == false) {
              continue;
            }
            final id = message.clientMsgID;
            if (id != null && id.isNotEmpty && !ids.add(id)) continue;
            collected.add(message);
          }
        }
        if (!_isCurrent(generation)) return;
        if (!fillPage ||
            collected.length >= pageSize ||
            (!rawHasMore && cloud?.cloudHasMore != true)) {
          break;
        }
        // A raw history batch may contain only a few matching media items.
        // Fill one visible page, or stop at the confirmed end of history.
        // Query changes cancel further work.
        await Future<void>.delayed(Duration.zero);
        if (!_isCurrent(generation)) return;
      } while (true);
      _results.addAll(collected.take(pageSize));
      _sortMediaNewestFirst();
      _pending = collected.skip(pageSize).toList();
      _nextRawPage = rawPage;
      _rawHasMore = rawHasMore;
    } catch (_) {
      if (!_isCurrent(generation)) return;
      // Commit the cursor only on success. Retry preserves existing results
      // and resumes the same page instead of restarting the whole search.
      _failed = true;
    } finally {
      if (_isCurrent(generation)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _loadKeyword() async {
    final generation = _generation;
    final query = _query;
    var before = _beforeSeq;
    var snapshot = _snapshotSeq;
    _loading = true;
    _failed = false;
    searchError = null;
    notifyListeners();
    try {
      while (_isCurrent(generation)) {
        final page = await _keywordApi!.search(
            isCurrent: () => _isCurrent(generation),
            conversationID: conversationID,
            keyword: query.keyword,
            beforeSeq: before,
            snapshotSeq: snapshot,
            startTime: query.localStart?.millisecondsSinceEpoch ?? 0,
            endTime: query.localEndExclusive?.millisecondsSinceEpoch ?? 0,
            senderIDs: query.senderIDs,
            types: query.keyword.isEmpty
                ? (query.messageTypes.isEmpty
                    ? {...query.sdkMessageTypes, 115, 117}.toList()
                    : query.messageTypes)
                : query.messageTypes.isEmpty
                    ? ChatKeywordSearchApi.contentTypes
                    : query.messageTypes);
        if (!_isCurrent(generation)) return;
        final matches = page.items
            .where((m) => query.accepts(m) && acceptResult?.call(m) != false)
            .toList();
        before = page.beforeSeq;
        snapshot = page.snapshotSeq;
        // Empty candidate pages may still have older matches. Continue using
        // the same snapshot, without fetching message history into the device.
        if (matches.isEmpty && page.hasMore) {
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        final ids = _results.map((m) => m.clientMsgID).toSet();
        _results.addAll(matches.where((m) => ids.add(m.clientMsgID)));
        _sortMediaNewestFirst();
        unawaited(_resolveSenders(matches, generation));
        _beforeSeq = before;
        _snapshotSeq = snapshot;
        _keywordHasMore = page.hasMore;
        break;
      }
    } on SearchApiException catch (error) {
      if (_isCurrent(generation)) {
        searchError = error.code;
        if (error.code == 1001) {
          _beforeSeq = _snapshotSeq = 0;
          _results.clear();
        }
        if (error.invalidatesContext) _results.clear();
        _failed = true;
      }
    } catch (_) {
      if (_isCurrent(generation)) _failed = true;
    } finally {
      if (_isCurrent(generation)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    super.dispose();
  }

  Future<void> _resolveSenders(List<Message> messages, int generation) async {
    bool current() =>
        _isCurrent(generation) && _keywordApi!.client.sessionCurrent;
    await _senderProfiles.enrich(messages, isCurrent: current);
    if (current()) notifyListeners();
  }
}
