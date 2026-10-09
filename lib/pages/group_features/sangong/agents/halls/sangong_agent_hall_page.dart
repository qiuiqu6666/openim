import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/group_feature_context.dart';
import '../../../widgets/group_feature_tokens.dart';
import '../../api/sangong_api_config.dart';
import '../../pages/sangong_agent_dashboard_page.dart';
import '../../pages/sangong_agent_personal_page.dart';
import '../../pages/sangong_agent_team_page.dart';
import '../../sangong_scope.dart';
import '../../services/authorization/sangong_access_policy.dart';
import '../../support/sangong_ui.dart';
import '../../widgets/app_back_button.dart';
import 'sangong_agent_hall.dart';
import 'sangong_agent_hall_banner.dart';

/// Each selection owns a separate HTTP/runtime scope. Replacing it cancels old
/// requests and drops cached balances, member lists, cursors and pending writes.
class SangongAgentHallPage extends StatefulWidget {
  const SangongAgentHallPage(
      {super.key,
      required this.featureContext,
      this.initialTenantId,
      this.onSelected,
      this.section = 'dashboard',
      this.pathPrefix = SangongApiConfig.pathPrefix});
  final GroupFeatureContext featureContext;
  final String? initialTenantId;
  final ValueChanged<String>? onSelected;
  final String section, pathPrefix;
  @override
  State<SangongAgentHallPage> createState() => _SangongAgentHallPageState();
}

class _SangongAgentHallPageState extends State<SangongAgentHallPage> {
  late final _discovery =
      SangongRuntime(widget.featureContext, pathPrefix: widget.pathPrefix);
  SangongRuntime? _selected;
  List<SangongAgentHall> _halls = const [];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load({bool restoreChoice = true}) async {
    if (_selected?.http.pendingCommandIds.isNotEmpty == true) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前操作结果尚未确认，请先核对或重试后再切换厅')));
      return;
    }
    final generation = ++_generation;
    final old = _selected;
    setState(() {
      _selected = null;
      _loading = true;
      _error = null;
    });
    old?.dispose();
    try {
      final current =
          await widget.featureContext.refreshCapabilities(force: true);
      if (!mounted || generation != _generation || !current.sessionCurrent()) {
        return;
      }
      if (!sangongAssignedAgentAccess(current)) throw StateError('当前代理权限已变化');
      _discovery.updateContext(current);
      final halls = await _discovery.agent.fetchHalls();
      if (!mounted || generation != _generation || !_discovery.isCurrent) {
        return;
      }
      setState(() {
        _halls = halls;
        _loading = false;
      });
      if (halls.length == 1) {
        _select(halls.single);
      } else if (restoreChoice) {
        for (final hall in halls) {
          if (hall.tenantId == widget.initialTenantId) {
            _select(hall);
            break;
          }
        }
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = DioErrorMessage.forApp(error);
      });
    }
  }

  void _select(SangongAgentHall hall) {
    if (!_discovery.isCurrent || !_halls.contains(hall)) return;
    final current = _discovery.featureContext.readCurrentContext();
    if (!sangongAssignedAgentAccess(current)) return;
    final old = _selected;
    setState(() {
      _selected = SangongRuntime(current,
          pathPrefix: widget.pathPrefix,
          selectedAgentTenantId: hall.tenantId,
          selectedAgentHallName: hall.name);
    });
    old?.dispose();
    widget.onSelected?.call(hall.tenantId);
  }

  @override
  void dispose() {
    _generation++;
    _selected?.dispose();
    _discovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _selected;
    if (runtime != null) {
      final Widget page = switch (widget.section) {
        'team' => const SangongAgentTeamPage(),
        'personal' => SangongAgentPersonalPage(
            imGroupId: widget.featureContext.groupID, embedded: true),
        _ =>
          SangongAgentDashboardPage(imGroupId: widget.featureContext.groupID),
      };
      return SangongAgentHallSelection(
          onChoose: () => _load(restoreChoice: false),
          child: SangongScope(
              key: ObjectKey(runtime), runtime: runtime, child: page));
    }
    return Scaffold(
      appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('选择厅'),
          actions: [
            IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                tooltip: '刷新')
          ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('重试'))
                ]))
              : _halls.isEmpty
                  ? const Center(child: Text('当前代理群暂无可查看的厅'))
                  : ListView(children: [
                      Padding(
                          padding: EdgeInsets.all(
                              GroupFeatureTokens.of(context).inset),
                          child: const Text('选择要查看的厅，积分、团队和返水均按厅分别显示。')),
                      for (final hall in _halls)
                        ListTile(
                            leading: const Icon(Icons.storefront_outlined),
                            title: Text(hall.name),
                            subtitle: Text('下注群：${hall.gameGroupId}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _select(hall)),
                    ]),
    );
  }
}
