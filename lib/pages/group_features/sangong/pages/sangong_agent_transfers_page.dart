import '../../widgets/group_feature_tokens.dart';
import 'package:openim_common/localization.dart';
import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_transfers_api.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_transfer.dart';
import 'package:openim/pages/group_features/sangong/widgets/app_back_button.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import '../widgets/authorization/sangong_agent_authorized_view.dart';

class SangongAgentTransfersPage extends StatefulWidget {
  const SangongAgentTransfersPage({super.key, this.api});
  final SangongTransfersApi? api;

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        SangongPageRoute(
          agent: true,
          context: context,
          settings: const RouteSettings(name: 'sangong_agent_transfers'),
          builder: (_) => const SangongAgentTransfersPage(),
        ),
      );

  @override
  State<SangongAgentTransfersPage> createState() => _TransfersState();
}

class _TransfersState extends State<SangongAgentTransfersPage> {
  late final _http = SangongScope.read(context).http;
  late final _session = AgentSessionSnapshot(SangongScope.read(context));
  late final _tenant = SangongScope.read(context).http.tenantId;
  final _batchController = TextEditingController();
  late final _api = widget.api ??
      SangongTransfersApi(
          dio: SangongScope.read(context).http.client,
          groupId: SangongScope.read(context).featureContext.groupID,
          scopedOptions: SangongScope.read(context).http.scopedOptions);
  String _direction = 'all';
  int? _sessionId;
  int _limit = 100;
  int _request = 0;
  bool _loading = true;
  String? _error;
  String? _batchError;
  List<SangongTransfer> _records = const [];

  bool get _current =>
      _session.isCurrent &&
      SangongScope.read(context).canViewRebateHistory &&
      _tenant == SangongScope.read(context).http.tenantId;

  @override
  void initState() {
    super.initState();
    _http.tenantIdListenable.addListener(_tenantChanged);
    _load();
  }

  void _tenantChanged() {
    if (mounted && !_current) {
      _request++;
      setState(() {
        _records = const [];
        _loading = false;
        _error = AppCopy.text('账号或群已切换，请重新进入划转记录');
      });
    }
  }

  @override
  void dispose() {
    _http.tenantIdListenable.removeListener(_tenantChanged);
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (!_current) {
      setState(() {
        _records = const [];
        _loading = false;
        _error = AppCopy.text('账号或群已切换，请重新进入划转记录');
      });
      return;
    }
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _records = const [];
    });
    try {
      final records = await _api.fetch(
        direction: _direction,
        limit: _limit,
        sessionId: _sessionId,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        if (_current) {
          _records = records;
        } else {
          _error = AppCopy.text('账号或群已切换，请重新进入划转记录');
        }
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = _current
            ? DioErrorMessage.forApp(error)
            : AppCopy.text('账号或群已切换，请重新进入划转记录');
      });
    }
  }

  void _applyBatch() {
    final text = _batchController.text.trim();
    final value = int.tryParse(text);
    if (text.isNotEmpty && (value == null || value <= 0)) {
      setState(() => _batchError = AppCopy.text('请输入大于 0 的批次 ID'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _batchError = null;
      _sessionId = text.isEmpty ? null : value;
      _limit = 100;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) => SangongAgentAuthorizedView(
        runtime: _session.runtime,
        session: _session,
        requireHistory: true,
        child: Scaffold(
          backgroundColor: GroupFeatureTokens.of(context).background,
          appBar: AppBar(
            centerTitle: true,
            leading: const AppBackButton(),
            title: Text(AppCopy.text('我的划转记录')),
          ),
          body: SafeArea(
              top: false,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          minimumSize: const WidgetStatePropertyAll(
                              Size(0, kMinInteractiveDimension)),
                          side: WidgetStatePropertyAll(BorderSide(
                              color: GroupFeatureTokens.of(context).divider)),
                        ),
                        segments: [
                          ButtonSegment(value: 'all', label: Text('全部')),
                          ButtonSegment(
                              value: 'out', label: Text(AppCopy.text('转出'))),
                          ButtonSegment(
                              value: 'in', label: Text(AppCopy.text('转入'))),
                        ],
                        selected: {_direction},
                        onSelectionChanged: (values) {
                          if (values.first == _direction) return;
                          setState(() {
                            _direction = values.first;
                            _limit = 100;
                          });
                          _load();
                        },
                      )),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _batchController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _applyBatch(),
                        decoration: InputDecoration(
                          hintText: AppCopy.text('输入批次 ID 筛选'),
                          filled: true,
                          fillColor: GroupFeatureTokens.of(context).surface,
                          prefixIcon: const Icon(Icons.search_rounded),
                          errorText: _batchError,
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  GroupFeatureTokens.of(context).cardRadius),
                              borderSide: BorderSide.none),
                          suffixIcon: IconButton(
                            tooltip: AppCopy.text('清除批次筛选'),
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _batchController.clear();
                              _applyBatch();
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(kMinInteractiveDimension,
                                kMinInteractiveDimension)),
                        onPressed: _applyBatch,
                        child: Text(AppCopy.text('查询'))),
                  ]),
                ),
                Expanded(child: _body()),
              ])),
        ),
      );

  Widget _body() {
    if (!_current) {
      return Center(child: Text(AppCopy.text('账号或群已切换，请重新进入划转记录')));
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: Text(AppCopy.text('重试'))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _records.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${_sessionId == null ? AppCopy.text('全部批次') : AppCopy.format('批次 ID {#0}', [
                        _sessionId
                      ])} · '
                '${AppCopy.format('显示最近 {#0} 条', [_records.length])}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }
          if (index <= _records.length) return _record(_records[index - 1]);
          if (_records.isEmpty) {
            final tokens = GroupFeatureTokens.of(context);
            return Padding(
              padding: EdgeInsets.symmetric(
                  vertical: tokens.inset * 3, horizontal: tokens.inset),
              child: Column(children: [
                CircleAvatar(
                    radius: tokens.inset * 2,
                    backgroundColor: tokens.surfaceAlt,
                    child: Icon(Icons.swap_horiz_rounded,
                        size: tokens.inset * 2, color: tokens.secondary)),
                SizedBox(height: tokens.inset),
                Text(AppCopy.text('暂无划转记录'),
                    style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: tokens.inset / 2),
                Text(
                    AppCopy.text(_sessionId != null
                        ? '当前批次没有符合条件的记录，可清除筛选查看'
                        : '完成积分划转后，可在这里查看明细'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tokens.secondary)),
                if (_sessionId != null)
                  TextButton(
                      onPressed: () {
                        _batchController.clear();
                        _applyBatch();
                      },
                      child: Text(AppCopy.text('查看全部批次'))),
              ]),
            );
          }
          if (_records.length >= _limit && _limit < 500) {
            return TextButton(
              onPressed: () {
                setState(() => _limit = 500);
                _load();
              },
              child: Text(AppCopy.text('查看最近 500 条')),
            );
          }
          return Center(
            child: Text(_records.length >= 500
                ? AppCopy.text('最多显示最近 500 条，可按批次查询')
                : AppCopy.text('已显示当前查询的全部记录')),
          );
        },
      ),
    );
  }

  Widget _record(SangongTransfer record) {
    final parsed = DateTime.tryParse(record.createdAt);
    final time = parsed == null
        ? (record.createdAt.isEmpty ? AppCopy.text('时间未知') : record.createdAt)
        : DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed.toLocal());
    final amount = record.amount == record.amount.roundToDouble()
        ? record.amount.toStringAsFixed(0)
        : record.amount.toStringAsFixed(2);
    final color = record.isOutgoing
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.primary;
    final tokens = GroupFeatureTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: tokens.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.cardRadius)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: EdgeInsets.all(tokens.inset),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
              width: 40,
              height: 40,
              child: ClipOval(
                child: record.counterpartAvatarUrl.isEmpty
                    ? const Icon(Icons.person_outline)
                    : Image.network(record.counterpartAvatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person_outline)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${record.isOutgoing ? AppCopy.text('转出给') : AppCopy.text('转入自')} ${sangongDisplayName(record.displayName, record.counterpartImUserId)}',
                style:
                    textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
              AppCopy.format(
                  '{#0}{#1} 积分', [record.isOutgoing ? '−' : '+', amount]),
              style: textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: color)),
          if (record.counterpartImUserId.isNotEmpty)
            SangongPublicAccount(userID: record.counterpartImUserId),
          SizedBox(height: tokens.inset / 2),
          Divider(color: tokens.divider),
          Text(time,
              style: textTheme.bodySmall?.copyWith(color: tokens.secondary)),
          Text('批次 ID：${record.sessionId}',
              style: textTheme.bodySmall?.copyWith(color: tokens.secondary)),
          if (record.referenceId.isNotEmpty)
            SelectableText(AppCopy.format('流水号：{#0}', [record.referenceId]),
                style: textTheme.bodySmall?.copyWith(color: tokens.secondary)),
        ]),
      ),
    );
  }
}
