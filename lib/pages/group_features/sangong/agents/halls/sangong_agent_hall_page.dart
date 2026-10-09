import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/group_feature_context.dart';
import '../../api/sangong_api_config.dart';
import '../../pages/sangong_agent_dashboard_page.dart';
import '../../pages/sangong_agent_personal_page.dart';
import '../../pages/sangong_agent_team_page.dart';
import '../../sangong_scope.dart';
import '../../services/authorization/sangong_access_policy.dart';
import '../../support/sangong_ui.dart';
import '../../widgets/app_back_button.dart';

/// Resolves exactly one fixed hall; the group never offers a tenant picker.
class SangongAgentHallPage extends StatefulWidget {
  const SangongAgentHallPage(
      {super.key,
      required this.featureContext,
      this.section = 'dashboard',
      this.pathPrefix = SangongApiConfig.pathPrefix});
  final GroupFeatureContext featureContext;
  final String section, pathPrefix;
  @override
  State<SangongAgentHallPage> createState() => _SangongAgentHallPageState();
}

class _SangongAgentHallPageState extends State<SangongAgentHallPage> {
  late final _discovery =
      SangongRuntime(widget.featureContext, pathPrefix: widget.pathPrefix);
  SangongRuntime? _bound;
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

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
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
      if (halls.isEmpty) throw StateError('当前代理群暂无可查看的数据');
      if (halls.length != 1 ||
          halls.single.tenantId != current.capabilities.sangong.tenantID) {
        throw StateError('代理群归属异常，请联系管理员');
      }
      final hall = halls.single;
      setState(() {
        _bound = SangongRuntime(current,
            pathPrefix: widget.pathPrefix,
            selectedAgentTenantId: hall.tenantId,
            selectedAgentHallName: hall.name);
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = DioErrorMessage.forApp(error);
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _bound?.dispose();
    _discovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _bound;
    if (runtime != null) {
      final Widget page = switch (widget.section) {
        'team' => const SangongAgentTeamPage(),
        'personal' => SangongAgentPersonalPage(
            imGroupId: widget.featureContext.groupID, embedded: true),
        _ =>
          SangongAgentDashboardPage(imGroupId: widget.featureContext.groupID),
      };
      return SangongScope(
          key: ObjectKey(runtime), runtime: runtime, child: page);
    }
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('三公代理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error ?? '暂无数据'),
              TextButton(onPressed: _load, child: const Text('重试')),
            ])),
    );
  }
}
