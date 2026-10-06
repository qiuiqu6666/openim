// Settlement flow adapted from 99chat agent_rebate_current_page.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../../data/group_feature_api.dart';
import '../../data/mark_six_repository.dart';
import 'agent_query_controller.dart';

class AgentRebateController extends AgentQueryController
    with WidgetsBindingObserver {
  AgentRebateController(super.repository) {
    WidgetsBinding.instance.addObserver(this);
  }
  bool submitting = false;
  bool polling = false;
  bool uncertain = false;
  bool restoring = false;
  bool statusRestored = false;
  Future<void>? _restoreWork;
  String status = '';
  String? applyError;
  bool _foreground = true;
  int _pollGeneration = 0;
  bool get settled => status.toUpperCase() == 'SUCCESS';
  bool get pending =>
      const {'PENDING', 'PROCESSING'}.contains(status.toUpperCase());
  bool get needsStatusQuery => !statusRestored || pending || uncertain;

  bool canApply({bool personal = false}) {
    if (!current ||
        restoring ||
        submitting ||
        polling ||
        loading ||
        error != null ||
        needsStatusQuery ||
        settled) {
      return false;
    }
    final raw = data?[personal ? 'personal' : 'summary'];
    final value = raw is Map
        ? raw[personal ? 'pendingRebate' : 'agentPendingRebate']
        : null;
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    return amount != null && amount.isFinite && amount > 0;
  }

  Future<void> initialize({bool force = false}) async {
    await Future.wait([refresh(force: force), restoreStatus()]);
  }

  String _parseStatus(Map<String, dynamic> response, {bool allowNone = false}) {
    final result = '${MarkSixRepository.payload(response)['status'] ?? ''}'
        .trim()
        .toUpperCase();
    if (!(const {'PENDING', 'PROCESSING', 'SUCCESS', 'FAILED'}
            .contains(result) ||
        (allowNone && result == 'NONE'))) {
      throw const FormatException('反水状态缺失或未知，请查询确认');
    }
    return result;
  }

  Future<void> restoreStatus() {
    if (!current || !_foreground || submitting || polling) {
      return Future.value();
    }
    final pendingWork = _restoreWork;
    if (pendingWork != null) return pendingWork;
    final generation = _pollGeneration;
    restoring = true;
    statusRestored = false;
    uncertain = true;
    applyError = null;
    notify();
    late final Future<void> work;
    work = repository
        .read('/me/agent/rebate/apply/status', force: true)
        .then((response) {
      if (!current || !_foreground || generation != _pollGeneration) return;
      status = _parseStatus(response, allowNone: true);
      statusRestored = true;
      uncertain = false;
    }).catchError((Object failure) {
      if (current && generation == _pollGeneration) {
        applyError = failure.toString();
      }
    }).whenComplete(() {
      if (current && generation == _pollGeneration) {
        restoring = false;
        notify();
      }
      if (identical(_restoreWork, work)) _restoreWork = null;
    });
    _restoreWork = work;
    return work;
  }

  Future<void> refresh({bool force = false}) =>
      load('/me/agent/rebate/current', force: force);
  Future<void> apply({bool personal = false}) async {
    if (!canApply(personal: personal)) return;
    submitting = true;
    applyError = null;
    notify();
    try {
      final result = await repository
          .post(personal ? '/me/rebate/apply' : '/me/agent/rebate/apply');
      if (!current) return;
      status = _parseStatus(result);
      if (pending) {
        await checkStatus(personal: personal);
      } else if (settled) {
        await refresh(force: true);
      } else if (status.toUpperCase() == 'FAILED') {
        applyError = '反水结算失败，请稍后重试';
      }
    } catch (failure) {
      if (current) {
        uncertain = failure is FormatException ||
            (failure is GroupFeatureException && failure.unknownResult);
        applyError = failure.toString();
      }
    } finally {
      if (current) {
        submitting = false;
        notify();
      }
    }
  }

  Future<void> checkStatus({bool personal = false}) async {
    if (!current || restoring || polling || !_foreground) return;
    final generation = ++_pollGeneration;
    polling = true;
    uncertain = true;
    applyError = null;
    notify();
    try {
      for (var attempt = 0; attempt < 30; attempt++) {
        if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
        if (!current || !_foreground || generation != _pollGeneration) return;
        final response = await repository.read(
            personal
                ? '/me/rebate/apply/status'
                : '/me/agent/rebate/apply/status',
            force: true);
        if (!current || !_foreground || generation != _pollGeneration) return;
        status = _parseStatus(response, allowNone: true);
        statusRestored = true;
        uncertain = false;
        notify();
        if (pending) continue;
        if (settled) await refresh(force: true);
        if (status.toUpperCase() == 'FAILED') applyError = '反水结算失败，请稍后重试';
        return;
      }
      if (current) applyError = '反水处理时间较长，请稍后重新查看状态';
    } catch (failure) {
      if (current && generation == _pollGeneration) {
        applyError = failure.toString();
      }
    } finally {
      if (current && generation == _pollGeneration) {
        polling = false;
        notify();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _pollGeneration++;
      polling = false;
      if (restoring) {
        restoring = false;
        uncertain = true;
      }
      notify();
    }
  }

  @override
  void dispose() {
    _pollGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
