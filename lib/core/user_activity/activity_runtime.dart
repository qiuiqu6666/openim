import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:openim_common/openim_common.dart' show Config, DataSp, dio;
import 'package:uuid/uuid.dart';

import 'activity_collector.dart';
import 'activity_schema.dart';
import 'connection_activity.dart';

class ActivityRuntime {
  ActivityRuntime._() {
    collector =
        ActivityCollector(upload: _upload, newID: () => const Uuid().v4());
    observer = ActivityNavigationObserver(this);
  }
  static final instance = ActivityRuntime._();
  late final ActivityCollector collector;
  late final ActivityNavigationObserver observer;
  final _transport = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
      followRedirects: false));
  bool Function()? _ready;
  Timer? _timer;
  Interceptor? _interceptor;
  CancelToken? _cancel;
  ActivitySession? _endedOwner;
  Map<String, String>? _clientInfo;
  Future<void>? _metadataLoading;
  String _homePage = 'conversations';
  final _connection = ConnectionActivity();

  static ActivitySession? _credentials() {
    final user = DataSp.userID, token = DataSp.chatToken;
    if (user == null || user.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    return (accountID: user, token: token, endpoint: Config.appAuthUrl);
  }

  void configure({required bool Function() sessionReady}) {
    _metadataLoading ??= _loadMetadata();
    _ready = sessionReady;
    _endedOwner = null;
    _interceptor ??= InterceptorsWrapper(onRequest: (options, handler) {
      try {
        _observeRequest(options);
      } catch (_) {/* Analytics cannot block business traffic. */}
      handler.next(options);
    });
    if (!dio.interceptors.contains(_interceptor)) {
      dio.interceptors.add(_interceptor!);
    }
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      sessionReadyNow();
      collector.tick();
    });
  }

  void sessionReadyNow({bool authenticated = false}) {
    final current = _credentials();
    if (authenticated) _endedOwner = null;
    if (current != null && current == _endedOwner) return;
    if (collector.owner != null && collector.owner != current) invalidate();
    if (_ready?.call() == true && current != null) {
      collector.bind(current);
      _drainConnections();
    }
  }

  void beginConnection(String userID, String imToken) => _observeConnection(() {
        _connection.begin(DataSp.userID == userID && DataSp.imToken == imToken
            ? _credentials()
            : null);
      });

  void connectionChanged({required bool connected}) => _observeConnection(() {
        if (_connection.owner != _credentials()) {
          _connection.reset();
          return;
        }
        connected ? _connection.connected() : _connection.lost();
        _drainConnections();
      });

  void sessionRestored(String userID, String imToken) => _observeConnection(() {
        if (DataSp.userID == userID &&
            DataSp.imToken == imToken &&
            _connection.owner == _credentials()) {
          _connection.restored();
          _drainConnections();
        }
      });

  void _observeConnection(void Function() record) {
    try {
      record();
    } catch (_) {
      // Optional observation must never interrupt SDK login or connection callbacks.
    }
  }

  void resetConnection() => _connection.reset();

  void _drainConnections() {
    if (collector.owner != _credentials()) return;
    for (final event in _connection.take(collector.owner)) {
      collector.connection(event);
    }
  }

  void setForeground(bool value) {
    collector.setForeground(value);
  }

  void markInteraction() {
    if (collector.owner == _credentials()) collector.interact();
  }

  void setHomeTab(int index) {
    _homePage = const {
          0: 'conversations',
          1: 'group',
          2: 'contacts',
          3: 'wallet',
          4: 'mine'
        }[index] ??
        'home';
    collector.visit(_homePage);
  }

  void visitRoute(String? route) {
    final page =
        route == '/home' ? _homePage : activityRoutes[route] ?? 'other';
    collector.visit(page);
  }

  // Capture the owner before awaiting an SDK operation; late completions from
  // an old account must never be attributed to the next account.
  ActivitySession? captureOwner() =>
      collector.owner != null && collector.owner == _credentials()
          ? collector.owner
          : null;
  void actionFor(ActivitySession? owner, String action,
      {String result = 'success'}) {
    if (owner != null && owner == collector.owner && owner == _credentials()) {
      collector.action(action, result: result);
    }
  }

  void _observeRequest(RequestOptions options) {
    final owner = captureOwner();
    if (owner == null ||
        !{'POST', 'PUT'}.contains(options.method.toUpperCase())) {
      return;
    }
    final base = Uri.parse(owner.endpoint), uri = options.uri;
    if (uri.scheme != base.scheme ||
        uri.host != base.host ||
        uri.port != base.port ||
        options.headers['token'] != owner.token) {
      return;
    }
    final basePath = base.path.replaceFirst(RegExp(r'/$'), '');
    if (!uri.path.startsWith('$basePath/')) return;
    final action = activityRequestAction(uri.path.substring(basePath.length));
    if (action == null) return;
    options.headers['X-Activity-Session'] = collector.sessionID;
    final operation = options.headers['operationID'];
    final operationID = operation is String && validActivityID(operation)
        ? operation
        : const Uuid().v4();
    options.headers['operationID'] = operationID;
    final body = options.data;
    final order = body is Map ? body['clientOrderID'] : null;
    collector.action(action,
        operationID: operationID,
        clientOrderID: order is String ? order : null);
  }

  Future<bool> _upload(ActivitySession owner, Map<String, Object> batch) async {
    if (owner != _credentials()) return true;
    final cancel = _cancel ??= CancelToken();
    try {
      final response = await _transport.post<dynamic>(
          '${owner.endpoint.replaceFirst(RegExp(r'/$'), '')}/chat/activity/events',
          data: {...batch, if (_clientInfo != null) 'client': _clientInfo!},
          cancelToken: cancel,
          options: Options(
              headers: {'token': owner.token, 'operationID': const Uuid().v4()},
              validateStatus: (_) => true));
      // Invalid/expired analytics are discarded quietly; 429/5xx back off.
      final status = response.statusCode ?? 0;
      if (status == 400 || status == 401 || status == 403 || status == 404) {
        return true;
      }
      return status >= 200 &&
          status < 300 &&
          response.data is Map &&
          response.data['errCode'] == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadMetadata() async {
    final info = <String, String>{};
    try {
      final package = await PackageInfo.fromPlatform();
      info['appVersion'] = '${package.version}+${package.buildNumber}';
    } catch (_) {}
    try {
      final device = await DeviceInfoPlugin().deviceInfo;
      if (device is AndroidDeviceInfo) {
        info['osVersion'] = 'Android ${device.version.release}';
        info['deviceModel'] = '${device.manufacturer} ${device.model}';
      }
      if (device is IosDeviceInfo) {
        info['osVersion'] = 'iOS ${device.systemVersion}';
        info['deviceModel'] = device.utsname.machine;
      }
    } catch (_) {}
    info.removeWhere((_, v) =>
        utf8.encode(v).length > 100 || v.contains(RegExp(r'[<>\x00-\x1F]')));
    _clientInfo = info;
  }

  void endSession() {
    _endedOwner = _credentials();
    resetConnection();
    invalidate();
  }

  void invalidate() {
    _cancel?.cancel();
    _cancel = null;
    collector.invalidate();
  }

  void dispose() {
    resetConnection();
    _timer?.cancel();
    _timer = null;
    _ready = null;
    if (_interceptor != null) dio.interceptors.remove(_interceptor);
    invalidate();
  }
}

class ActivityNavigationObserver extends NavigatorObserver {
  ActivityNavigationObserver(this.runtime);
  final ActivityRuntime runtime;
  final List<Route<dynamic>> _pages = [];
  void _sync() {
    if (_pages.isNotEmpty) runtime.visitRoute(_pages.last.settings.name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages.add(route);
      _sync();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pages.remove(route)) _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pages.remove(route)) _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (index >= 0) {
      _pages.removeAt(index);
      if (newRoute is PageRoute) _pages.insert(index, newRoute);
    } else if (newRoute is PageRoute) {
      _pages.add(newRoute);
    }
    _sync();
  }
}
