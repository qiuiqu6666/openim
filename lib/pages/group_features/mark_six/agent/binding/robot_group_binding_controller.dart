import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../../models/group_feature_context.dart';
import '../../data/diagnostics/mark_six_api_debug_log.dart';
import 'robot_group_binding.dart';

/// One chat owns this read; capability refreshes do not restart the request.
class RobotGroupBindingController extends ChangeNotifier
    with WidgetsBindingObserver {
  RobotGroupBindingController(this.context) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  final GroupFeatureContext context;
  RobotGroupBinding? binding;
  String? error;
  bool loading = false;
  bool _disposed = false, _foreground = true;
  int _generation = 0;
  Future<void>? _work;
  CancelToken? _token;

  bool get current => !_disposed && context.sessionCurrent();
  bool get bound => current && binding?.bound == true;
  bool _valid(int generation) => current && generation == _generation;

  void _notify() {
    if (current) notifyListeners();
  }

  Future<void> load() {
    if (!current || !_foreground || context.groupID.isEmpty) {
      MarkSixApiDebugLog.event('绑定查询跳过', {
        'groupId': context.groupID,
        'sessionCurrent': current,
        'foreground': _foreground,
      });
      return Future.value();
    }
    final pending = _work;
    if (pending != null) {
      MarkSixApiDebugLog.event('合并正在进行的绑定查询', {'groupId': context.groupID});
      return pending;
    }
    final generation = ++_generation;
    final token = _token = CancelToken();
    binding = null;
    error = null;
    loading = true;
    late final Future<void> work;
    work = _load(generation, token).whenComplete(() {
      if (identical(_work, work)) {
        _work = null;
        _token = null;
      }
    });
    _work = work;
    _notify();
    return work;
  }

  Future<void> _load(int generation, CancelToken token) async {
    try {
      // This Chat endpoint requires Bearer auth; the group is already in the path.
      final data = await MarkSixApiDebugLog.trace(() => context.api.requestData(
            '/me/robot/groups/${Uri.encodeComponent(context.groupID)}',
            useBearerAuth: true,
            cancelToken: token,
          ));
      if (!_valid(generation)) {
        MarkSixApiDebugLog.event('忽略旧绑定响应', {'groupId': context.groupID});
        return;
      }
      if (data is! Map<String, dynamic>) {
        throw const FormatException('群绑定状态格式错误');
      }
      binding =
          RobotGroupBinding.fromJson(data, expectedGroupID: context.groupID);
      MarkSixApiDebugLog.event('绑定结果', {
        'groupId': context.groupID,
        'bound': binding!.bound,
        'enabled': binding!.enabled,
        'showFloatingEntry': bound,
      });
    } catch (failure) {
      MarkSixApiDebugLog.event('绑定查询未完成', {
        'groupId': context.groupID,
        'errorType': '${failure.runtimeType}',
        'currentResponse': _valid(generation),
        'showFloatingEntry': false,
      });
      if (_valid(generation)) error = failure.toString();
    } finally {
      if (_valid(generation)) {
        loading = false;
        _notify();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _generation++;
      _token?.cancel('Chat binding read suspended');
      _token = null;
      _work = null;
      binding = null;
      loading = false;
      _notify();
    } else if (current) {
      unawaited(load());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _token?.cancel('Chat binding read closed');
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
