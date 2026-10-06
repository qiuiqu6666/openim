import '../../../models/group_feature_context.dart';
import '../../api/binding/sangong_group_tenant_api.dart';
import '../../models/binding/sangong_group_tenant_state.dart';
import '../authorization/sangong_operation_scope.dart';

/// Current game-group registration, separate from the account's default config.
class SangongGroupTenantStore {
  SangongGroupTenantStore(
      {required this.readContext,
      required this.isCurrent,
      required this.onChanged});

  final GroupFeatureContext Function() readContext;
  final bool Function() isCurrent;
  final void Function() onChanged;
  SangongGroupTenantState? state;
  Object? error;
  bool loading = false;
  DateTime? _fetched;
  Future<SangongGroupTenantState>? _pending;
  int _revision = 0;

  Future<SangongGroupTenantState> refresh({bool force = false}) {
    if (!isCurrent()) {
      return Future.error(StateError('账号或群上下文已变化，请重新进入'));
    }
    final pending = _pending;
    if (pending != null) return pending;
    final cached = state;
    if (!force &&
        cached != null &&
        _fetched != null &&
        DateTime.now().difference(_fetched!) < const Duration(minutes: 5)) {
      return Future.value(cached);
    }
    final context = readContext();
    final scope = SangongOperationScope.capture(context, null);
    final privilege = context.privilege;
    final privilegeRevision = privilege.revision;
    final revision = _revision;
    bool current() =>
        isCurrent() &&
        revision == _revision &&
        context.sessionCurrent() &&
        scope.sameAccountAndGroup(readContext()) &&
        identical(privilege, readContext().privilege) &&
        privilegeRevision == privilege.revision;
    loading = true;
    error = null;
    onChanged();
    late final Future<SangongGroupTenantState> task;
    task = SangongGroupTenantApi().fetch(context).then((value) {
      if (!current()) throw StateError('账号或群上下文已变化，请重新进入');
      state = value;
      _fetched = DateTime.now();
      return value;
    }).catchError((Object failure, StackTrace stack) {
      if (current()) {
        state = null;
        _fetched = null;
        error = failure;
      }
      Error.throwWithStackTrace(failure, stack);
    }).whenComplete(() {
      if (identical(_pending, task)) {
        _pending = null;
        loading = false;
        onChanged();
      }
    });
    _pending = task;
    return task;
  }

  void invalidate() {
    _revision++;
    state = null;
    error = null;
    loading = false;
    _fetched = null;
    _pending = null;
  }

  void applySaved(SangongGroupTenantState value) {
    if (!isCurrent()) return;
    _revision++;
    _pending = null;
    loading = false;
    error = null;
    state = value;
    _fetched = DateTime.now();
    onChanged();
  }
}
