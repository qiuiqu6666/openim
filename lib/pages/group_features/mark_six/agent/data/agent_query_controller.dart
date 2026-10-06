import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/mark_six_repository.dart';

/// Query projection shared by current/history/detail pages. It never owns auth.
class AgentQueryController extends ChangeNotifier {
  AgentQueryController(this.repository) {
    _events = repository.context.events.listen((event) {
      if (_disposed ||
          repository.privateCurrent ||
          '${event['groupID'] ?? ''}' != repository.context.groupID) {
        return;
      }
      _generation++;
      data = null;
      loading = false;
      _work = null;
      notifyListeners();
    });
  }
  final MarkSixRepository repository;
  Map<String, dynamic>? data;
  String? error;
  bool loading = false;
  bool _disposed = false;
  int _generation = 0;
  String? _requestKey;
  Future<void>? _work;
  StreamSubscription<Map<String, dynamic>>? _events;
  bool get current => !_disposed && repository.privateCurrent;
  void notify() {
    if (current) notifyListeners();
  }

  Future<void> load(String path,
      {Map<String, dynamic> query = const {}, bool force = false}) {
    if (!current) return Future.value();
    final key = '$path|$query';
    if (_requestKey == key && _work != null) return _work!;
    final generation = ++_generation;
    _requestKey = key;
    loading = true;
    error = null;
    data = null;
    notify();
    late final Future<void> work;
    work = repository.read(path, query: query, force: force).then((response) {
      if (current && generation == _generation) {
        data = MarkSixRepository.payload(response);
      }
    }).catchError((Object failure) {
      if (current && generation == _generation) error = failure.toString();
    }).whenComplete(() {
      if (current && generation == _generation) {
        loading = false;
        notify();
      }
      if (identical(_work, work)) _work = null;
    });
    _work = work;
    return work;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _events?.cancel();
    super.dispose();
  }
}
