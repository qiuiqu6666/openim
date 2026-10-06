import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/group_feature_api.dart';
import '../../models/group_feature_context.dart';

/// Keeps a live route on the account-owned permission cache after SDK updates.
/// Public watching remains independent of private management/push permissions.
class LivePermissionState extends ChangeNotifier {
  LivePermissionState(GroupFeatureContext context)
      : _initial = context,
        _context = context {
    _events = context.events.listen(_onEvent);
  }

  final GroupFeatureContext _initial;
  GroupFeatureContext _context;
  GroupFeatureContext get context => _context;
  bool _closed = false, _active = true;
  bool loading = false;
  Object? error;
  Future<GroupFeatureContext>? _request;
  StreamSubscription<Map<String, dynamic>>? _events;

  bool get sessionCurrent => !_closed && _initial.sessionCurrent();
  bool get current => sessionCurrent && _context.capabilitiesCurrent();

  void setActive(bool active) => _active = active;

  void _onEvent(Map<String, dynamic> event) {
    if (_closed) return;
    if (!sessionCurrent) {
      notifyListeners();
      return;
    }
    if (event['key'] == 'groupFeatureCapabilitiesResolved') {
      final next = _initial.readCurrentContext();
      if (next.groupID == _initial.groupID &&
          next.currentUserID == _initial.currentUserID &&
          identical(next.api, _initial.api) &&
          next.sessionCurrent() &&
          next.capabilitiesCurrent()) {
        _context = next;
        error = null;
        notifyListeners();
      }
      return;
    }
    if (!current) {
      // Clear sensitive UI immediately; never keep stale keys while refreshing.
      notifyListeners();
      if (_active && _initial.reloadCapabilities != null) {
        unawaited(refresh().then<void>((_) {}, onError: (Object _) {}));
      }
    }
  }

  Future<GroupFeatureContext> refresh({bool force = false}) {
    if (_request != null) return _request!;
    if (!sessionCurrent) {
      return Future.error(const GroupFeatureException('登录状态已变化，请重新进入',
          code: 'SESSION_CHANGED', authRequired: true));
    }
    loading = true;
    error = null;
    notifyListeners();
    late Future<GroupFeatureContext> request;
    request = _refresh(force).whenComplete(() {
      if (!identical(_request, request)) return;
      _request = null;
      loading = false;
      if (!_closed) notifyListeners();
    });
    return _request = request;
  }

  Future<GroupFeatureContext> _refresh(bool force) async {
    try {
      final next = await _context.refreshCapabilities(force: force);
      if (!sessionCurrent) {
        throw const GroupFeatureException('登录状态已变化，请重新进入',
            code: 'SESSION_CHANGED', authRequired: true);
      }
      _context = next;
      return next;
    } catch (failure) {
      if (!_closed) error = failure;
      rethrow;
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_events?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
