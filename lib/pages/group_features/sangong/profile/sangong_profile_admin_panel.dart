import 'package:flutter/material.dart';
import '../../data/group_feature_api.dart';
import '../identity/widgets/sangong_identity_view.dart';
import '../models/sangong_admin_models.dart';
import '../models/sangong_game_settings.dart';
import '../models/sangong_admin_realtime_state.dart';
import '../sangong_scope.dart';
import '../services/authorization/sangong_operation_scope.dart';
import '../support/sangong_ui.dart' show DioErrorMessage, ToastUtils;
import '../utils/sangong_banker_setup_input.dart';

import 'sangong_profile_admin_layout.dart';

/// The 99chat controls, backed by one authorized OpenIM account/group/tenant.
class SangongProfilePanel extends StatefulWidget {
  const SangongProfilePanel(
      {super.key,
      required this.userID,
      this.nickname = '',
      this.embedded = false});
  final String userID;
  final String nickname;
  final bool embedded;
  @override
  State<SangongProfilePanel> createState() => _SangongProfilePanelState();
}

class _SangongProfilePanelState extends State<SangongProfilePanel> {
  final _points = TextEditingController();
  final _banker = TextEditingController();
  final _joint = TextEditingController();
  SangongAdminUserReport? _user;
  SangongAdminSession? _session;
  SangongGameSettings? _settings;
  Map<String, dynamic> _detail = {};
  SangongRuntime? _runtime;
  SangongOperationScope? _scope;
  String? _error;
  bool _loading = true, _writing = false;
  int _generation = 0, _writeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _joint.addListener(_inputChanged);
    _banker.addListener(_inputChanged);
  }

  void _inputChanged() {
    if (mounted && _current) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final runtime =
        context.dependOnInheritedWidgetOfExactType<SangongScope>()?.notifier;
    if (runtime == null || !runtime.canManage) {
      _runtime = runtime;
      _clearPrivateState();
    } else if (!identical(runtime, _runtime) ||
        _scope == null ||
        !_scope!.matches(runtime.featureContext, runtime.http.tenantId)) {
      _clearPrivateState();
      _runtime = runtime;
      _load();
    }
  }

  @override
  void didUpdateWidget(SangongProfilePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userID != widget.userID) {
      _clearPrivateState();
      _load();
    }
  }

  void _clearPrivateState() {
    _generation++;
    _writeGeneration++;
    _scope = null;
    _user = null;
    _session = null;
    _settings = null;
    _detail = {};
    _error = null;
    _loading = false;
    _writing = false;
    _points.clear();
    _banker.clear();
    _joint.clear();
  }

  @override
  void dispose() {
    _generation++;
    _writeGeneration++;
    _joint.removeListener(_inputChanged);
    _banker.removeListener(_inputChanged);
    _points.dispose();
    _banker.dispose();
    _joint.dispose();
    super.dispose();
  }

  bool get _current =>
      mounted &&
      _runtime?.canManage == true &&
      _scope?.matches(_runtime!.featureContext, _runtime!.http.tenantId) ==
          true &&
      widget.userID.isNotEmpty &&
      widget.userID != _runtime?.featureContext.currentUserID;

  bool get _canSubmit =>
      _current &&
      !_loading &&
      !_writing &&
      _error == null &&
      _settings != null &&
      _session != null;

  Future<void> _load() async {
    final runtime = _runtime, target = widget.userID;
    if (runtime == null ||
        !runtime.canManage ||
        target.isEmpty ||
        target == runtime.featureContext.currentUserID) {
      return;
    }
    final generation = ++_generation;
    final scope = _scope = SangongOperationScope.capture(
        runtime.featureContext, runtime.http.tenantId);
    bool current() =>
        _current &&
        generation == _generation &&
        identical(runtime, _runtime) &&
        widget.userID == target &&
        scope.matches(runtime.featureContext, runtime.http.tenantId);
    setState(() {
      _loading = true;
      _error = null;
      _user = null;
      _session = null;
      _settings = null;
      _detail = {};
    });
    try {
      final results = await Future.wait<Object>([
        runtime.admin.fetchUserDetail(target),
        runtime.admin.fetchEventsSnapshot(),
      ]);
      if (!current()) return;
      final detail = results[0] as Map<String, dynamic>;
      final state = results[1] as SangongAdminRealtimeState;
      final rawUser = detail['user'];
      final user = rawUser is Map
          ? SangongAdminUserReport.fromJson(Map<String, dynamic>.from(rawUser))
          : null;
      if (user != null && user.imUserId != target) {
        throw StateError('游戏资料与当前用户不匹配');
      }
      setState(() {
        _user = user;
        _detail = detail;
        _session = SangongAdminSession(
            status: state.status, session: state.session, round: state.round);
        _settings = state.settings;
      });
    } catch (error) {
      if (current()) setState(() => _error = DioErrorMessage.forApp(error));
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  /// A failed write is never repeated by retry; retry only reads current state.
  Future<void> _submit(String action, String message,
      Future<void> Function(SangongRuntime, bool Function()) write,
      {TextEditingController? clear}) async {
    if (!_canSubmit) return;
    final runtime = _runtime!, target = widget.userID;
    final scope = SangongOperationScope.capture(
        runtime.featureContext, runtime.http.tenantId);
    final generation = ++_writeGeneration;
    bool current() =>
        _current &&
        generation == _writeGeneration &&
        identical(runtime, _runtime) &&
        target == widget.userID &&
        scope.matches(runtime.featureContext, runtime.http.tenantId);
    setState(() => _writing = true);
    try {
      if (!current()) return;
      await write(runtime, current);
      if (!current()) return;
      clear?.clear();
      await _load();
    } catch (error) {
      if (current()) ToastUtils.toast(DioErrorMessage.forApp(error));
    } finally {
      if (mounted && generation == _writeGeneration) {
        setState(() => _writing = false);
      }
    }
  }

  void _invalid(String message) {
    if (_current) ToastUtils.toast(message);
  }

  int? _positiveAmount(TextEditingController controller, String label) {
    final amount = int.tryParse(controller.text.trim());
    if (amount == null || amount <= 0) {
      _invalid('请输入大于 0 的整数$label');
      return null;
    }
    return amount;
  }

  SangongCoBankMember? _member(SangongAdminSession? session) =>
      session?.round?.coBank.memberForImUserId(widget.userID) ??
      (_user?.userId == null
          ? null
          : session?.round?.coBank.memberForUserId(_user!.userId!));

  Future<void> _creditOrDebit({required bool credit}) async {
    if (!_canSubmit) return;
    final amount = _positiveAmount(_points, '金额');
    if (amount == null) return;
    final target = widget.userID;
    final action = credit ? '上分' : '下分';
    await _submit(action, '为$_displayName $action $amount 积分？',
        (runtime, current) async {
      if (!credit) {
        final session = await runtime.admin.fetchSession();
        if (!current()) return;
        final round = session.round;
        if (round != null &&
            round.id > 0 &&
            !round.isRoundClosed &&
            (round.bankerImUserId == target || _member(session) != null)) {
          throw StateError('当前庄／合庄对局尚未结算，暂不可下分');
        }
      }
      if (!current()) return;
      final result = credit
          ? await runtime.admin.credit(imUserId: target, amount: amount)
          : await runtime.admin.debit(imUserId: target, amount: amount);
      final returnedIm = result.ledger?.imUserId ?? '';
      if (returnedIm.isNotEmpty && returnedIm != target) {
        _unknownResult();
      }
    }, clear: _points);
  }

  Never _unknownResult() => throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
      code: 'UNKNOWN_RESULT', unknownResult: true);

  bool _validDoor(int door) {
    final doors = _settings?.doorCount;
    if (doors == null || door < 1 || door > doors) {
      _invalid('庄门需在 1～${doors ?? '—'} 之间');
      return false;
    }
    return true;
  }

  Future<void> _assignBanker({required bool setLimit}) async {
    if (!_canSubmit) return;
    final parsed = parseSangongBankerSetupText(_banker.text);
    int? door = parsed.door, limit = parsed.limit;
    if (setLimit && !parsed.hasExplicitLimit) {
      limit = parsed.door;
      door = _session?.round?.bankerDoor;
    }
    if (door == null || (setLimit && limit == null)) {
      _invalid(setLimit ? '请先定庄或输入「庄门.限额」' : '请输入庄门（如 2 或 2.5000）');
      return;
    }
    if (!_validDoor(door)) return;
    if (limit != null && limit < 0) {
      _invalid('展示限额须为大于等于 0 的整数');
      return;
    }
    final target = widget.userID;
    final roundId = _session?.round?.id ?? 0;
    if (roundId <= 0) {
      _invalid("请先开机");
      return;
    }
    if (setLimit &&
        !parsed.hasExplicitLimit &&
        _session?.round?.bankerImUserId != target) {
      _invalid('请先在当前页面为该用户定庄');
      return;
    }
    final savedLimit = limit ?? _session?.round?.bankerLimit ?? 0;
    await _submit('定庄／限额', '', (runtime, current) async {
      final result = await runtime.admin.assignBanker(
          roundId: roundId,
          imUserId: target,
          door: door!,
          limit: savedLimit,
          nickname: _displayName);
      if (!current()) return;
      if (result.round?.bankerImUserId != target ||
          result.round?.bankerDoor != door ||
          result.round?.bankerLimit != savedLimit) {
        _unknownResult();
      }
    }, clear: _banker);
  }

  Future<void> _coBank({required bool remove}) async {
    if (!_canSubmit) return;
    final id = _user?.userId;
    if (id == null || id <= 0) {
      _invalid('缺少游戏账号编号');
      return;
    }
    final amount = remove ? null : _positiveAmount(_joint, '合庄金额');
    if (!remove && amount == null) return;
    final round = _session?.round;
    if (round == null || round.id <= 0 || round.isRoundClosed) {
      _invalid('当前无有效局');
      return;
    }
    await _submit(remove ? '取消合庄' : '设置合庄', '', (runtime, current) async {
      if (remove) {
        await runtime.admin.removeCoBank(roundId: round.id, userId: id);
      } else {
        await runtime.admin
            .addCoBank(roundId: round.id, userId: id, amount: amount!);
      }
    }, clear: _joint);
  }

  Future<void> _send({required bool coBank}) {
    final roundId = _session?.round?.id ?? 0;
    if (roundId <= 0) {
      _invalid('当前无有效局');
      return Future.value();
    }
    return _submit(coBank ? '发送合庄' : '发送定庄', '', (runtime, current) async {
      if (!current()) return;
      if (coBank) {
        await runtime.admin.sendCoBankNotification(roundId: roundId);
      } else {
        await runtime.admin.sendBankerNotification(roundId: roundId);
      }
    });
  }

  String get _displayName => widget.nickname.trim().isNotEmpty
      ? widget.nickname.trim()
      : _user?.nickname.trim().isNotEmpty == true
          ? _user!.nickname.trim()
          : widget.userID;

  String get _parentUserID {
    final parent = _detail['parent'];
    if (parent is! Map) return '';
    return '${parent['imUserId'] ?? parent['im_user_id'] ?? ''}'.trim();
  }

  String _parentLabel(SangongDisplayIdentity? identity) {
    final parent = _detail['parent'];
    if (parent is! Map) return '';
    final nickname = '${parent['nickname'] ?? ''}'.trim();
    if (_parentUserID.isEmpty && nickname.isEmpty) return '';
    return sangongDisplayName(
        identity?.nickname.trim().isNotEmpty == true
            ? identity!.nickname
            : nickname,
        _parentUserID);
  }

  String? get _bankerSummary {
    if (_session == null) return null;
    final round = _session!.round;
    if (round == null) return '庄 不限额';
    final door = round.bankerDoor;
    final limit = round.bankerLimit;
    return '${door == null ? '庄' : '庄$door门'} ${limit == null || limit == 0 ? '不限额' : '限额$limit'}';
  }

  SangongCoBank? get _coBankPreview {
    final saved = _session?.round?.coBank;
    if (saved == null) return null;
    return saved;
  }

  double? get _sharePercent => _coBankPreview == null
      ? null
      : _coBankPreview!.memberForImUserId(widget.userID)?.sharePercent ??
          _coBankPreview!.memberForUserId(_user?.userId ?? 0)?.sharePercent ??
          0;

  String? get _coBankSummary {
    final round = _session?.round;
    if (round == null) return null;
    final coBank = _coBankPreview!;
    final members = coBank.members;
    final labels = members.map((member) =>
        '【${member.nickname.trim().isEmpty ? member.imUserId.isEmpty ? member.userId : member.imUserId : member.nickname.trim()}】${member.sharePercent.toStringAsFixed(2)}%');
    return '庄池：${coBank.poolTotal} · 合庄庄家: ${labels.isEmpty ? '—' : labels.join('，')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const SizedBox.shrink();
    return SangongIdentityView(
      key: ValueKey((widget.userID, _scope?.token)),
      userID: _parentUserID,
      builder: (identity) => _buildLayout(_parentLabel(identity)),
    );
  }

  Widget _buildLayout(String parentLabel) {
    return SangongProfileAdminLayout(
        embedded: widget.embedded,
        pointsController: _points,
        bankerController: _banker,
        jointController: _joint,
        loading: _loading,
        disabled: !_canSubmit,
        points: _user?.balance,
        parentLabel: parentLabel,
        rebatePer10000: _user?.rebatePer10000,
        bankerSummary: _bankerSummary,
        sharePercent: _sharePercent,
        coBankSummary: _coBankSummary,
        error: _error,
        onRetry: _loading || _writing ? null : _load,
        onCredit: () => _creditOrDebit(credit: true),
        onDebit: () => _creditOrDebit(credit: false),
        onAssignBanker: _banker.text.trim().isEmpty
            ? null
            : () => _assignBanker(setLimit: false),
        onSetLimit: _banker.text.trim().isEmpty
            ? null
            : () => _assignBanker(setLimit: true),
        onSendBanker: () => _send(coBank: false),
        onSetCoBank: () => _coBank(remove: false),
        onRemoveCoBank: _sharePercent == 0 && _member(_session) == null
            ? null
            : () => _coBank(remove: true),
        onSendCoBank: () => _send(coBank: true));
  }
}
