// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_member_detail_page.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/widgets/app_back_button.dart';
import '../widgets/authorization/sangong_agent_authorized_view.dart';

class SangongAgentPersonalPage extends StatefulWidget {
  const SangongAgentPersonalPage(
      {super.key, required this.imGroupId, this.imUserId});
  final String imGroupId;
  final String? imUserId;

  @visibleForTesting
  static String resolveCurrentImUserId(BuildContext context) {
    return SangongScope.read(context).featureContext.currentUserID.trim();
  }

  static String _personalErrorText(Object error) {
    final text = DioErrorMessage.forApp(error);
    if (text.contains('Incorrect result size') || text.contains('用户不存在')) {
      return '当前账号在该群没有代理数据';
    }
    return text;
  }

  static Future<void> open(BuildContext context,
      {required String imGroupId, String? imUserId}) async {
    final session = AgentSessionSnapshot(SangongScope.read(context));
    if (!session.isCurrent) return;
    try {
      final id = resolveCurrentImUserId(context);
      if (id.isEmpty) throw StateError('未找到当前登录用户');
      final data = await SangongScope.read(context)
          .agent
          .fetchSangongMemberDashboard(imUserId: id);
      final member = data['member'];
      if (member is! Map) throw StateError('个人数据格式无效');
      if (!context.mounted || !session.isCurrent) return;
      await Navigator.of(context).push(SangongPageRoute(
        agent: true,
        context: context,
        settings: const RouteSettings(name: 'sangong_agent_member_detail'),
        builder: (_) => SangongAgentMemberDetailPage(
            member: SangongTeamMemberDto.fromJson(
                Map<String, dynamic>.from(member))),
      ));
    } catch (e) {
      if (context.mounted && session.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_personalErrorText(e))));
      }
    }
  }

  @override
  State<SangongAgentPersonalPage> createState() => _State();
}

class _State extends State<SangongAgentPersonalPage> {
  late final _accountSession = AgentSessionSnapshot(SangongScope.read(context));
  bool get _isCurrentSession => mounted && _accountSession.isCurrent;

  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || !_isCurrentSession) return;
    try {
      final id = SangongAgentPersonalPage.resolveCurrentImUserId(context);
      if (id.isEmpty) throw StateError('未找到当前登录用户');
      final data = await SangongScope.read(context)
          .agent
          .fetchSangongMemberDashboard(imUserId: id);
      final member = data['member'];
      if (member is! Map) throw StateError('个人数据格式无效');
      if (!mounted || !_isCurrentSession) return;
      final detail = SangongAgentMemberDetailPage(
        member:
            SangongTeamMemberDto.fromJson(Map<String, dynamic>.from(member)),
      );
      await Navigator.of(context).pushReplacement(
        SangongPageRoute(
          agent: true,
          context: context,
          settings: const RouteSettings(name: 'sangong_agent_member_detail'),
          builder: (_) => detail,
        ),
      );
      if (mounted && _isCurrentSession) setState(() => _loading = false);
    } catch (e) {
      if (mounted && _isCurrentSession) {
        setState(() {
          _error = SangongAgentPersonalPage._personalErrorText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SangongAgentAuthorizedView(
        runtime: _accountSession.runtime,
        session: _accountSession,
        child: Scaffold(
          appBar:
              AppBar(leading: const AppBackButton(), title: const Text('个人数据')),
          body: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Text(_error ?? '暂无数据')),
        ),
      );
}
