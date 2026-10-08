import 'package:flutter/foundation.dart';
import '../../sangong_scope.dart';
import '../../api/sangong_v2_api.dart';
import '../../services/authorization/sangong_operation_scope.dart';
import '../../support/sangong_ui.dart';

/// One visible report query, with fixed group/permission ownership and cursor
/// pagination. Never combines financial pages from different server versions.
class ReportQueryController extends ChangeNotifier {
  ReportQueryController(this.runtime, this.resource,
      {this.listKey, Map<String, dynamic> query = const {}})
      : query = Map.of(query),
        scope = SangongOperationScope.capture(
            runtime.featureContext, runtime.http.tenantId) {
    runtime.addListener(_checkScope);
  }
  final SangongRuntime runtime;
  final String resource;
  final String? listKey;
  final SangongOperationScope scope;
  Map<String, dynamic> query;
  Map<String, dynamic> data = {};
  List<Map<String, dynamic>> rows = [];
  String? error;
  int cursor = 0, _generation = 0;
  bool busy = false, invalid = false, _disposed = false;
  bool get current =>
      !_disposed &&
      !invalid &&
      runtime.canManage &&
      scope.matches(runtime.featureContext, runtime.http.tenantId);

  void _checkScope() {
    if (_disposed || current) return;
    invalid = true;
    _generation++;
    data = {};
    rows = [];
    cursor = 0;
    busy = false;
    error = '当前群或管理权限已变化，请重新进入';
    notifyListeners();
  }

  Future<void> load({bool more = false}) async {
    if (!current || busy || more && cursor == 0) return;
    final generation = ++_generation;
    final before = more ? cursor : 0;
    busy = true;
    error = null;
    if (!more) {
      data = {};
      rows = [];
      cursor = 0;
    }
    notifyListeners();
    try {
      final result = await SangongV2Api(runtime.http).read(resource, query: {
        ...query,
        if (listKey != null) 'limit': 50,
        if (before > 0) 'beforeId': before,
      });
      if (!current || generation != _generation) return;
      if (result['version'] is! int) throw const FormatException('报表版本缺失');
      final next = listKey == null ? 0 : result['nextBeforeId'];
      if (next is! int || next < 0 || more && next > 0 && next >= before) {
        throw const FormatException('报表分页无效');
      }
      if (more && data['version'] != result['version']) {
        data = {};
        rows = [];
        cursor = 0;
        throw StateError('数据已变化，请刷新后重新查询');
      }
      final raw = listKey == null ? const [] : result[listKey];
      if (raw is! List || raw.any((row) => row is! Map)) {
        throw const FormatException('报表明细格式无效');
      }
      rows = [
        ...rows,
        ...raw.map((row) => Map<String, dynamic>.from(row as Map))
      ];
      data = result;
      cursor = next;
    } catch (failure) {
      if (current && generation == _generation) {
        error = DioErrorMessage.forApp(failure);
      }
    } finally {
      if (current && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> replaceQuery(Map<String, dynamic> value) {
    _generation++;
    busy = false;
    query = Map.of(value);
    return load();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    runtime.removeListener(_checkScope);
    super.dispose();
  }
}
