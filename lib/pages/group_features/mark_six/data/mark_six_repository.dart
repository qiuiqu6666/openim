// Reference routes: 99chat lottery_live_api.dart and agent_rebate_api.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import '../../models/group_feature_context.dart';
import '../models/mark_six_json.dart';

class MarkSixSessionEnded implements Exception {
  const MarkSixSessionEnded();
  @override
  String toString() => '登录状态已变更，请重新进入';
}

/// Owns no credential or socket. The host's transport owns account isolation.
class MarkSixRepository {
  MarkSixRepository(this.context,
      {DateTime Function()? now, this.cacheTTL = const Duration(seconds: 30)})
      : _now = now ?? DateTime.now;
  final GroupFeatureContext context;
  final DateTime Function() _now;
  final Duration cacheTTL;
  final _pending = <String, Future<Map<String, dynamic>>>{};
  final _cache = <String, Map<String, dynamic>>{};
  final _cachedAt = <String, DateTime>{};
  bool _closed = false;
  bool get current => !_closed && context.sessionCurrent();
  bool get privateCurrent => current && context.capabilitiesCurrent();
  String get machineCode {
    final cap = context.capabilities.markSix;
    final feature = context.features.markSix;
    for (final value in [
      cap.machineCode,
      feature.machineCode,
      cap.gameID,
      feature.gameID
    ]) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  Map<String, dynamic> get headers => {'X-Group-Id': context.groupID};
  void guard({bool private = false}) {
    if (!current || (private && !privateCurrent)) {
      throw const MarkSixSessionEnded();
    }
  }

  Future<Map<String, dynamic>> read(String path,
      {Map<String, dynamic> query = const {}, bool force = false}) {
    final private = path.startsWith('/me/');
    guard(private: private);
    final key =
        '$path|${query.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final existing = _pending[key];
    if (existing != null) return existing;
    final stamp = _cachedAt[key];
    if (!force && stamp != null && _now().difference(stamp) < cacheTTL) {
      return Future.value(_cache[key]);
    }
    late final Future<Map<String, dynamic>> work;
    final response = path.startsWith('/api/v1/lotteries/')
        ? context.api.getEnvelope(path, query: query, headers: headers)
        : context.api.get(path, query: query, headers: headers);
    work = response.then((result) {
      guard(private: private);
      // Group headers are always scoped; explicit response IDs must agree.
      final responseGroup = result['groupID'] ?? result['groupId'];
      if (responseGroup != null && '$responseGroup' != context.groupID) {
        throw const FormatException('接口返回群上下文不匹配');
      }
      final payload = MarkSixRepository.payload(result);
      if (query['userId'] != null &&
          payload['targetUserId'] != null &&
          '${payload['targetUserId']}' != '${query['userId']}') {
        throw const FormatException('接口返回下级用户不匹配');
      }
      if (query['userId'] != null &&
          markSixRows(payload).any((row) =>
              row['userId'] != null &&
              '${row['userId']}' != '${query['userId']}')) {
        throw const FormatException('接口返回下级记录不匹配');
      }
      for (final field in ['startDate', 'endDate']) {
        if (query[field] != null &&
            payload[field] != null &&
            query[field] != payload[field]) {
          throw const FormatException('接口返回日期范围不匹配');
        }
      }
      if (!_cache.containsKey(key) && _cache.length >= 64) {
        final oldest = _cache.keys.first;
        _cache.remove(oldest);
        _cachedAt.remove(oldest);
      }
      _cache[key] = result;
      _cachedAt[key] = _now();
      return result;
    }).whenComplete(() {
      if (identical(_pending[key], work)) _pending.remove(key);
    });
    _pending[key] = work;
    return work;
  }

  Future<Map<String, dynamic>> lottery(String resource,
      {Map<String, dynamic> query = const {}, bool force = false}) {
    if (machineCode.isEmpty) throw StateError('本群尚未配置六合彩机器码');
    return read('/api/v1/lotteries/mark-six-demo/$resource',
        query: {'machineCode': machineCode, ...query}, force: force);
  }

  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic> body = const {}}) async {
    guard(private: path.startsWith('/me/'));
    final result = await context.api.post(path, body: body, headers: headers);
    guard(private: path.startsWith('/me/'));
    invalidate();
    return result;
  }

  Future<Map<String, dynamic>> update(
      String path, Map<String, dynamic> body) async {
    guard(private: path.startsWith('/me/'));
    final result = await context.api.put(path, body: body, headers: headers);
    guard(private: path.startsWith('/me/'));
    invalidate();
    return result;
  }

  void invalidate() {
    _cache.clear();
    _cachedAt.clear();
  }

  void close() {
    _closed = true;
    invalidate();
    _pending.clear();
  }

  static Map<String, dynamic> payload(Map<String, dynamic> response) =>
      response['data'] is Map ? markSixMap(response['data']) : response;
}
