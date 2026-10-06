// Adapted from 99chat LotteryLiveSession; networking belongs to the host.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/mark_six_draw.dart';
import '../models/mark_six_json.dart';
import '../../models/group_features.dart';
import 'mark_six_repository.dart';

class MarkSixController extends ChangeNotifier with WidgetsBindingObserver {
  MarkSixController(this.repository);
  final MarkSixRepository repository;
  Map<String, dynamic>? config;
  List<MarkSixDraw> draws = [];
  List<Map<String, dynamic>> predictions = [];
  Map<String, dynamic>? statistics;
  bool loading = false;
  String? error;
  String? predictionError;
  bool predictionsLoading = false;
  bool predictionsHasMore = false;
  int predictionPage = 0;
  int predictionTotal = 0;
  int window = 40;
  int _generation = 0;
  int _predictionGeneration = 0;
  int _users = 0;
  bool _disposed = false;
  bool _foreground = true;
  bool _predictionVisible = false;
  bool scopeInvalidated = false;
  Future<void>? _refreshWork;
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _eventDebounce;
  DateTime _serverNow = DateTime.now().toUtc();
  final Stopwatch _clock = Stopwatch()..start();
  bool get current => !_disposed && !scopeInvalidated && repository.current;
  bool get ready => config != null;
  MarkSixDraw? get latest => draws.where((draw) => draw.drawn).firstOrNull;
  MarkSixDraw? get currentRound => draws.firstOrNull;
  DateTime now() => _serverNow.add(_clock.elapsed);
  bool _valid(int generation) => current && generation == _generation;
  void _notify() {
    if (current) notifyListeners();
  }

  void attach() {
    if (_disposed || ++_users != 1) return;
    WidgetsBinding.instance.addObserver(this);
    _events = repository.context.events.listen((event) {
      if (!current ||
          '${event['groupID'] ?? event['groupId'] ?? ''}' !=
              repository.context.groupID) {
        return;
      }
      final type =
          '${event['key'] ?? event['type'] ?? event['eventType'] ?? ''}';
      if (type == 'groupFeaturesChanged' || type == 'groupGameChanged') {
        final data = markSixMap(event['data']);
        final next = GroupFeatures.fromJson(
            event['groupFeatures'] ?? data['groupFeatures']);
        final before = repository.context.features;
        if (next.valid &&
            next.revision > before.revision &&
            _publicFingerprint(next.markSix) !=
                _publicFingerprint(before.markSix)) {
          scopeInvalidated = true;
          _generation++;
          _predictionGeneration++;
          config = null;
          draws = [];
          predictions = [];
          loading = false;
          predictionsLoading = false;
          _eventDebounce?.cancel();
          _events?.cancel();
          _events = null;
          repository.close();
          notifyListeners();
          return;
        }
      }
      if (!type.contains('lottery') &&
          !type.contains('mark-six') &&
          !type.contains('markSix') &&
          type != 'groupGameChanged') {
        return;
      }
      repository.invalidate();
      _eventDebounce?.cancel();
      if (!_foreground) return;
      _eventDebounce = Timer(const Duration(milliseconds: 200), () {
        if (current && _users > 0) unawaited(refresh(force: true));
      });
    });
    unawaited(refresh());
  }

  Object _publicFingerprint(GroupGameFeature feature) => (
        feature.enabled,
        feature.drawHistoryEntry,
        feature.machineCode,
        feature.gameID,
        feature.tenantID
      );

  void detach() {
    if (_users == 0 || --_users > 0) return;
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _events = null;
    _eventDebounce?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _eventDebounce?.cancel();
    if (state == AppLifecycleState.resumed && _users > 0 && current) {
      unawaited(refresh(force: true));
    }
  }

  Future<void> refresh({bool force = false}) {
    if (!current) return Future.value();
    final pending = _refreshWork;
    if (pending != null) return pending;
    late final Future<void> work;
    work = _refresh(force).whenComplete(() {
      if (identical(work, _refreshWork)) _refreshWork = null;
    });
    _refreshWork = work;
    return work;
  }

  Future<void> _refresh(bool force) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      final responses = await Future.wait([
        repository.lottery('config', force: force),
        repository.lottery('draws', query: {'limit': 100}, force: force),
      ]);
      if (!_valid(generation)) return;
      final firstGroup = responses.first['groupUid'];
      if (firstGroup != null &&
          responses.any((r) => r['groupUid'] != firstGroup)) {
        throw const FormatException('开奖接口实例不匹配');
      }
      final parsedConfig = MarkSixRepository.payload(responses[0]);
      final drawData = responses[1]['data'] ?? responses[1];
      if (parsedConfig.isEmpty || (drawData is! Map && drawData is! List)) {
        throw const FormatException('开奖数据格式错误');
      }
      final rows = markSixRows(drawData);
      for (final row in rows) {
        if (row['issue'] == null || row['status'] == null) {
          throw const FormatException('开奖期号或状态缺失');
        }
        final special =
            int.tryParse('${markSixMap(row['attributes'])['special']}');
        if (row['status'] == 'drawn' &&
            (special == null || special < 1 || special > 49)) {
          throw const FormatException('开奖号码缺失或超出范围');
        }
      }
      rows.sort((a, b) => ((b['sequence'] as num?)?.toInt() ?? 0)
          .compareTo((a['sequence'] as num?)?.toInt() ?? 0));
      final seen = <String>{};
      config = parsedConfig;
      draws = rows
          .where((row) => seen.add('${row['issue']}'))
          .take(101)
          .map(MarkSixDraw.new)
          .toList();
      final stamp = responses[1]['serverTime'] ?? parsedConfig['serverTime'];
      if (stamp is num) {
        _serverNow =
            DateTime.fromMillisecondsSinceEpoch(stamp.toInt(), isUtc: true);
        _clock
          ..reset()
          ..start();
      }
      // Predictions remain lazy; a changed draw invalidates their cached window.
      _predictionGeneration++;
      predictionsLoading = false;
      predictions = [];
      predictionPage = 0;
      predictionsHasMore = false;
      statistics = null;
      if (_predictionVisible && _foreground && current) {
        unawaited(loadPredictions(force: force));
      }
    } catch (failure) {
      if (_valid(generation)) error = failure.toString();
    } finally {
      if (_valid(generation)) {
        loading = false;
        _notify();
      }
    }
  }

  void setPredictionVisible(bool visible) {
    _predictionVisible = visible;
    if (visible && current) unawaited(loadPredictions());
  }

  Future<void> selectWindow(int value) async {
    final choices = (config?['windowOptions'] is List
        ? config!['windowOptions'] as List
        : [6, 12, 20, 30, 40]);
    if (!choices.contains(value) ||
        value < 1 ||
        value > 100 ||
        value == window) {
      return;
    }
    window = value;
    _predictionGeneration++;
    predictionsLoading = false;
    predictions = [];
    predictionPage = 0;
    statistics = null;
    _notify();
    await loadPredictions();
  }

  Future<void> loadPredictions({bool more = false, bool force = false}) async {
    if (!current ||
        predictionsLoading ||
        (!force && !more && predictionPage > 0) ||
        (more && !predictionsHasMore)) {
      return;
    }
    final generation = ++_predictionGeneration;
    final scope = _generation;
    final page = more ? predictionPage + 1 : 1;
    predictionsLoading = true;
    predictionError = null;
    _notify();
    try {
      final response = await repository.lottery('predictions',
          query: {'window': window, 'limit': 20, 'page': page}, force: force);
      final data = MarkSixRepository.payload(response);
      if (!_valid(scope) || generation != _predictionGeneration) return;
      if (data['page'] != page ||
          data['window'] != window ||
          data['hasMore'] is! bool) {
        throw const FormatException('预测分页上下文错误');
      }
      final rows = markSixRows(data);
      if (rows.length > 20 || (data['hasMore'] == true && rows.isEmpty)) {
        throw const FormatException('预测分页未前进');
      }
      final merged = more ? [...predictions, ...rows] : rows;
      if (more &&
          rows.every((row) => predictions
              .any((previous) => previous['issue'] == row['issue']))) {
        throw const FormatException('预测分页未前进');
      }
      final seen = <String>{};
      predictions =
          merged.where((row) => seen.add('${row['issue']}')).take(100).toList();
      predictionPage = page;
      predictionTotal =
          (data['totalCount'] as num?)?.toInt() ?? predictions.length;
      predictionsHasMore = data['hasMore'] == true && predictions.length < 100;
    } catch (failure) {
      if (_valid(scope) && generation == _predictionGeneration) {
        predictionError = failure.toString();
      }
    } finally {
      if (_valid(scope) && generation == _predictionGeneration) {
        predictionsLoading = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _predictionGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _eventDebounce?.cancel();
    _clock.stop();
    repository.close();
    super.dispose();
  }
}
