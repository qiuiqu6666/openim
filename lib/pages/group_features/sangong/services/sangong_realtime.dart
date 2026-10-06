import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../sangong_scope.dart';
import '../models/sangong_admin_realtime_state.dart';
import '../support/sangong_ui.dart';
import '../utils/sangong_sse_parser.dart';
import '../api/diagnostics/sangong_api_debug_log.dart';

/// One reference-counted stream per account/group/authorized tenant. Snapshot
/// on subscribe/reconnect/resume; no unconditional 15-second recovery polling.
class SangongRealtime extends ChangeNotifier with WidgetsBindingObserver {
  SangongRealtime(this.runtime);
  final SangongRuntime runtime;
  SangongAdminRealtimeState? latestState;
  String? error;
  int _owners = 0, _generation = 0, _attempt = 0, _stateEpoch = 0;
  bool _foreground = true, _disposed = false;
  String? _tenant;
  StreamSubscription<String>? _stream;
  CancelToken? _cancel;
  Timer? _retry, _idle;
  Future<void>? _snapshot;
  final _parser = SangongSseParser();
  bool get _canRun =>
      !_disposed && _owners > 0 && _foreground && runtime.canManage;
  int get ownerCount => _owners;
  void acquire() {
    if (_disposed) return;
    if (++_owners != 1) return;
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    runtime.http.tenantIdListenable.addListener(_tenantChanged);
    _connect();
  }

  void release() {
    if (_owners == 0 || _disposed) return;
    if (--_owners != 0) return;
    WidgetsBinding.instance.removeObserver(this);
    runtime.http.tenantIdListenable.removeListener(_tenantChanged);
    _stop();
  }

  void _tenantChanged() {
    latestState = null;
    error = null;
    _attempt = 0;
    _stop();
    _connect();
  }

  void _stop() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _idle?.cancel();
    _idle = null;
    _stream?.cancel();
    _stream = null;
    _cancel?.cancel('Sangong stream suspended');
    _cancel = null;
    _snapshot = null;
    _parser.reset();
  }

  void _connect() {
    if (!_canRun) return;
    final generation = _generation;
    _tenant = runtime.http.tenantId;
    final token = _cancel = CancelToken();
    unawaited(refreshSnapshot());
    _stream = runtime.featureContext.api
        .eventStream(runtime.http.requestPath('/api/v1/admin/events/stream'),
            headers: runtime.http.requestHeaders(),
            baseUrlOverride: runtime.http.baseUrlOverride,
            useBearerAuth: true,
            diagnostics: SangongApiDebugLog.create(),
            cancelToken: token)
        .listen((chunk) {
      if (!_current(generation)) return;
      _armIdle(generation);
      _parser.feed(chunk, (event, data) {
        if (event != 'state' && event != 'message') return;
        try {
          final json = jsonDecode(data);
          if (json is! Map) throw const FormatException('Invalid SSE state');
          final map = Map<String, dynamic>.from(json);
          final raw = map['state'] ?? map;
          if (raw is! Map ||
              !raw.containsKey('version') ||
              raw['settings'] is! Map) {
            throw const FormatException('Invalid SSE state');
          }
          _accept(SangongAdminRealtimeState.fromRequiredJson(
              Map<String, dynamic>.from(raw)));
          _attempt = 0;
        } catch (failure) {
          error = DioErrorMessage.forApp(failure);
          notifyListeners();
          // A malformed/gapped state triggers one merged calibration request.
          unawaited(refreshSnapshot());
        }
      });
    }, onError: (Object failure) {
      if (_current(generation)) _recover(failure);
    }, onDone: () {
      if (_current(generation)) _recover(StateError('三公实时连接已中断'));
    });
    _armIdle(generation);
  }

  bool _current(int generation) =>
      _canRun && generation == _generation && _tenant == runtime.http.tenantId;
  void _armIdle(int generation) {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 45), () {
      if (_current(generation)) _recover(StateError('三公实时连接超时'));
    });
  }

  void _recover(Object failure) {
    error = DioErrorMessage.forApp(failure);
    _stop();
    if (!_canRun) return;
    notifyListeners();
    const delays = [1, 2, 5, 10, 30];
    final delay = delays[_attempt.clamp(0, delays.length - 1)];
    _attempt++;
    _retry = Timer(Duration(seconds: delay), _connect);
  }

  Future<void> refreshSnapshot() {
    if (!_canRun) return Future.value();
    final pending = _snapshot;
    if (pending != null) return pending;
    final generation = _generation, epoch = _stateEpoch;
    late final Future<void> task;
    task = runtime.admin.fetchEventsSnapshot().then((state) {
      if (!_current(generation)) return;
      // HTTP cannot roll back an SSE event which overtook the request.
      if (epoch != _stateEpoch &&
          state.version <= (latestState?.version ?? 0)) {
        return;
      }
      _accept(state);
    }).catchError((Object failure) {
      if (_current(generation)) {
        error = DioErrorMessage.forApp(failure);
        notifyListeners();
      }
    }).whenComplete(() {
      if (identical(_snapshot, task)) _snapshot = null;
    });
    _snapshot = task;
    return task;
  }

  void _accept(SangongAdminRealtimeState state) {
    final previous = latestState;
    // version is the service's tenant snapshot version, not group ex revision.
    if (previous != null && state.version <= previous.version) {
      if (state.version == previous.version && error != null) {
        error = null;
        notifyListeners();
      }
      return;
    }
    latestState = state;
    _stateEpoch++;
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
