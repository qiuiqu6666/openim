import 'package:flutter/foundation.dart';
import '../data/compensation_api.dart';
import '../models/compensation_detail.dart';

class CompensationController extends ChangeNotifier {
  CompensationController(
      {required this.source, required this.id, Duration Function()? elapsed}) {
    _watch.start();
    _elapsed = elapsed ?? (() => _watch.elapsed);
  }
  final CompensationSource source;
  final String id;
  final _watch = Stopwatch();
  late final Duration Function() _elapsed;
  Duration _origin = Duration.zero;
  CompensationDetail? detail;
  bool busy = false, uncertain = false, synchronized = false, _disposed = false;
  int _lifecycle = 0;
  String? error;
  String? _notifiedReceipt;
  Duration get remaining {
    final d = detail;
    if (d == null || d.activityEnded) return Duration.zero;
    final left = d.deadline.difference(d.serverTime.add(_elapsed() - _origin));
    return left.isNegative ? Duration.zero : left;
  }

  bool get expired => detail != null && remaining == Duration.zero;
  CompensationState? get state => detail?.state == CompensationState.claimed
      ? CompensationState.claimed
      : expired
          ? CompensationState.ended
          : detail?.state;
  bool get canClaim =>
      source.sessionValid &&
      synchronized &&
      !busy &&
      !uncertain &&
      state == CompensationState.unclaimed;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void tick() {
    if (!source.sessionValid) {
      detail = null;
      synchronized = false;
      error = '登录状态已变化，请返回首页重新进入';
    }
    _emit();
  }

  void suspend() {
    _lifecycle++;
    synchronized = false;
    _emit();
  }

  void _accept(CompensationDetail result) {
    if (result.id != id) throw const FormatException('Activity mismatch');
    detail = result;
    _origin = _elapsed();
    synchronized = true;
    uncertain = false;
    error = null;
    if (result.state == CompensationState.claimed &&
        _notifiedReceipt != result.receiptID) {
      _notifiedReceipt = result.receiptID;
      source.notifyCredited();
    }
  }

  Future<void> refresh() async {
    if (busy || _disposed) return;
    final lifecycle = _lifecycle;
    busy = true;
    synchronized = false;
    error = null;
    _emit();
    try {
      final result = await source.detail(id);
      if (!_disposed && source.sessionValid) {
        _accept(result);
        if (lifecycle != _lifecycle) synchronized = false;
      }
    } catch (_) {
      if (!_disposed) error = uncertain ? '领取结果待确认，请重新查询' : '活动加载失败，请检查网络后重试';
    } finally {
      busy = false;
      if (!source.sessionValid) {
        detail = null;
        error = '登录状态已变化，请返回首页重新进入';
      }
      _emit();
    }
  }

  Future<void> claim() async {
    if (!canClaim) return;
    final lifecycle = _lifecycle;
    busy = true;
    error = null;
    _emit();
    try {
      final result = await source.claim(id);
      if (!_disposed && source.sessionValid) {
        _accept(result);
        if (lifecycle != _lifecycle) synchronized = false;
        if (result.state != CompensationState.claimed) {
          error = '暂未领取成功，请核对当前活动状态';
        }
      }
    } catch (_) {
      // A timed-out write can have committed. Query before offering another claim.
      uncertain = true;
      synchronized = false;
      if (!_disposed && source.sessionValid) {
        try {
          final result = await source.detail(id);
          if (!_disposed && source.sessionValid) {
            _accept(result);
            if (result.state == CompensationState.unclaimed) {
              error = '暂未领取成功，服务或网络繁忙，请稍后重试';
            }
            if (lifecycle != _lifecycle) synchronized = false;
          }
        } catch (_) {
          error = '领取结果待确认，请查询结果，无需重复领取';
        }
      }
    } finally {
      busy = false;
      if (!source.sessionValid) {
        detail = null;
        synchronized = false;
        error = '登录状态已变化，请返回首页重新进入';
      }
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _watch.stop();
    super.dispose();
  }
}
