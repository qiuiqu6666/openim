import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'chat_history_search_source.dart';

/// Owns one search page's state; dispose it with its page.
class ChatHistorySearchController extends ChangeNotifier {
  ChatHistorySearchController({
    required this.conversationID,
    ChatHistorySearchSource? source,
    this.acceptResult,
  }) : source = source ?? OpenIMChatHistorySearchSource();

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
  ChatHistorySearchQuery get query => _query;
  bool get loading => _loading;
  bool get failed => _failed;
  bool get hasSearched => _hasSearched;
  bool get hasMore => _hasSearched && (_pending.isNotEmpty || _rawHasMore);

  /// Clearing the input also invalidates any in-flight keyword search.
  void clear() {
    if (_disposed) return;
    ++_generation;
    _query = const ChatHistorySearchQuery();
    _results.clear();
    _pending = [];
    _nextRawPage = 1;
    _rawHasMore = true;
    _loading = false;
    _failed = false;
    _hasSearched = false;
    notifyListeners();
  }

  Future<void> search(ChatHistorySearchQuery query) async {
    if (_disposed) return;
    final snapshot = query.snapshot();
    ++_generation;
    _query = snapshot;
    _results.clear();
    _pending = [];
    _nextRawPage = 1;
    _rawHasMore = true;
    _hasSearched = true;
    await _load();
  }

  Future<void> loadMore() async {
    if (_disposed || _loading || !hasMore) return;
    await _load();
  }

  Future<void> retry() async {
    if (_disposed || _loading || !_failed) return;
    await _load();
  }

  Future<void> _load() async {
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
      while (collected.length < pageSize && rawHasMore) {
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
          if (!query.accepts(message) || acceptResult?.call(message) == false) {
            continue;
          }
          final id = message.clientMsgID;
          if (id != null && id.isNotEmpty && !ids.add(id)) continue;
          collected.add(message);
        }
      }
      if (!_isCurrent(generation)) return;
      _results.addAll(collected.take(pageSize));
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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
