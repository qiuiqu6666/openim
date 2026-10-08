import 'dart:async';
import 'package:flutter/widgets.dart';
import '../sangong_scope.dart';
import '../models/sangong_admin_realtime_state.dart';
import '../support/sangong_ui.dart';
import 'realtime/sangong_state_event.dart';

/// One account/group subscription. HTTP calibrates entry, reconnect and resume;
/// authenticated bot messages carry subsequent public snapshots over OpenIM.
class SangongRealtime extends ChangeNotifier with WidgetsBindingObserver {
  SangongRealtime(this.runtime);
  final SangongRuntime runtime;
  SangongAdminRealtimeState? latestState;
  String? error;
  int _owners = 0, _generation = 0, _attempt = 0;
  bool _foreground = true, _disposed = false;
  String? _tenant;
  String _botUserID = '';
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _retry;
  Timer? _calibration;
  Future<void>? _snapshot;
  final _earlyEvents = <Map<String, dynamic>>[];
  bool get _canRun =>
      !_disposed && _owners > 0 && _foreground && runtime.canManage;
  int get ownerCount => _owners;

  void acquire() {
    if (_disposed || ++_owners != 1) return;
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    runtime.http.tenantIdListenable.addListener(_tenantChanged);
    _connect();
  }

  void release() {
    if (_owners == 0 || _disposed || --_owners != 0) return;
    WidgetsBinding.instance.removeObserver(this);
    runtime.http.tenantIdListenable.removeListener(_tenantChanged);
    _stop();
  }

  void _tenantChanged() {
    latestState = null;
    error = null;
    _botUserID = '';
    _attempt = 0;
    _stop();
    _connect();
  }

  void _stop() {
    _generation++;
    _calibration?.cancel();
    _calibration = null;
    _retry?.cancel();
    _retry = null;
    _events?.cancel();
    _events = null;
    _snapshot = null;
    _earlyEvents.clear();
  }

  void _connect() {
    if (!_canRun) return;
    _tenant = runtime.http.tenantId;
    final generation = _generation;
    // Quiet mutations (bets, refunds, banker reset) intentionally have no chat
    // message. Calibrate only while this foreground group has an active owner.
    _calibration = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_current(generation) && error == null) {
        unawaited(refreshSnapshot());
      }
    });
    _events = runtime.featureContext.events.listen((event) {
      if (!_current(generation) ||
          event['groupID'] != runtime.featureContext.groupID) {
        return;
      }
      if (event['key'] == 'imReconnected') {
        unawaited(refreshSnapshot());
      } else if (event['key'] == 'sangongStateMessage') {
        if (_botUserID.isEmpty) {
          if (_earlyEvents.length == 64) _earlyEvents.removeAt(0);
          _earlyEvents.add(event);
        } else {
          _acceptEvent(event);
        }
      }
    });
    unawaited(refreshSnapshot());
  }

  bool _current(int generation) =>
      _canRun && generation == _generation && _tenant == runtime.http.tenantId;

  void _acceptEvent(Map<String, dynamic> event) {
    final state = readSangongStateEvent(event,
        groupID: runtime.featureContext.groupID,
        botUserID: _botUserID,
        currentVersion: latestState?.version ?? -1);
    if (state != null) _accept(state);
  }

  Future<void> refreshSnapshot() {
    if (!_canRun) return Future.value();
    final pending = _snapshot;
    if (pending != null) return pending;
    final generation = _generation;
    late final Future<void> task;
    task = runtime.admin.fetchEventsSnapshot().then((state) {
      if (!_current(generation)) return;
      if (state.groupID != runtime.featureContext.groupID ||
          state.botUserID.isEmpty ||
          state.schemaVersion != 2) {
        throw const FormatException('Invalid Sangong group snapshot');
      }
      _botUserID = state.botUserID;
      _attempt = 0;
      _retry?.cancel();
      _accept(state);
      final buffered = List<Map<String, dynamic>>.of(_earlyEvents);
      _earlyEvents.clear();
      for (final event in buffered) {
        _acceptEvent(event);
      }
    }).catchError((Object failure) {
      if (!_current(generation)) return;
      error = DioErrorMessage.forApp(failure);
      notifyListeners();
      const delays = [1, 2, 5, 10, 30];
      final delay = delays[_attempt.clamp(0, delays.length - 1)];
      _attempt++;
      _retry?.cancel();
      _retry = Timer(Duration(seconds: delay), () {
        unawaited(refreshSnapshot());
      });
    }).whenComplete(() {
      if (identical(_snapshot, task)) _snapshot = null;
    });
    _snapshot = task;
    return task;
  }

  void _accept(SangongAdminRealtimeState state) {
    if (latestState != null && state.version <= latestState!.version) {
      if (state.version == latestState!.version && error != null) {
        error = null;
        notifyListeners();
      }
      return;
    }
    latestState = state;
    error = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_foreground == resumed) return;
    _foreground = resumed;
    _stop();
    if (resumed) _connect();
  }

  @override
  void dispose() {
    if (_disposed) return;
    WidgetsBinding.instance.removeObserver(this);
    if (_owners > 0) {
      runtime.http.tenantIdListenable.removeListener(_tenantChanged);
    }
    _owners = 0;
    _disposed = true;
    _stop();
    super.dispose();
  }
}
