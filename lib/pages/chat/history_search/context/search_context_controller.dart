import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../cloud/chat_keyword_search_api.dart';
import 'search_context_api.dart';

class SearchContextController extends ChangeNotifier {
  SearchContextController(this.hit, {SearchContextApi? api})
      : api = api ?? SearchContextApi();
  final CloudKeywordMessage hit;
  final SearchContextApi api;
  final _messages = <Message>[];
  List<Message> get messages => UnmodifiableListView(_messages);
  bool loading = false, beforeEnd = true, afterEnd = true;
  bool initialized = false, _disposed = false;
  int? errorCode;
  String _before = '', _after = '';
  int _generation = 0;

  Future<void> reload() => _load(null);
  Future<void> more(bool before) async {
    if (!initialized || (before ? beforeEnd : afterEnd)) return;
    await _load(before);
  }

  Future<void> _load(bool? before) async {
    if (_disposed || loading) return;
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    loading = true;
    errorCode = null;
    if (before == null) {
      _messages.clear();
      initialized = false;
    }
    notifyListeners();
    try {
      var cursor = before == null
          ? null
          : before
              ? _before
              : _after;
      final visited = <String?>{cursor};
      while (current()) {
        final page = await api.fetch(hit,
            cursor: cursor, before: before ?? true, isCurrent: current);
        if (!current()) return;
        final end = before == null
            ? true
            : before
                ? page.beforeEnd
                : page.afterEnd;
        final next = before == true ? page.beforeCursor : page.afterCursor;
        if (before != null && !end && !visited.add(next)) {
          throw const FormatException('Repeated context cursor');
        }
        final seqs = _messages.map((m) => m.seq).toSet();
        final ids = _messages.map((m) => m.clientMsgID).toSet();
        final added = page.messages
            .where((m) => !seqs.contains(m.seq) && !ids.contains(m.clientMsgID))
            .toList();
        if (before != null && added.isEmpty && !end) {
          cursor = next;
          continue;
        }
        if (before == null) {
          _messages.addAll(page.messages);
          _before = page.beforeCursor;
          _after = page.afterCursor;
          beforeEnd = page.beforeEnd;
          afterEnd = page.afterEnd;
        } else {
          _messages.addAll(added);
          _messages.sort((a, b) => a.seq!.compareTo(b.seq!));
          if (before) {
            _before = next;
            beforeEnd = end;
          } else {
            _after = next;
            afterEnd = end;
          }
        }
        initialized = true;
        break;
      }
    } on SearchApiException catch (error) {
      if (!current()) return;
      errorCode = error.code;
      if (error.invalidatesContext || error.code == 1001) {
        _messages.clear();
        initialized = false;
        beforeEnd = afterEnd = true;
      }
    } catch (_) {
      if (current()) errorCode = -1;
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void invalidateSession() {
    if (_disposed) return;
    ++_generation;
    _messages.clear();
    initialized = false;
    loading = false;
    errorCode = 1501;
    beforeEnd = afterEnd = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
