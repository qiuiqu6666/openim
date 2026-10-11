import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;
import '../sangong_scope.dart';
import '../models/sangong_admin_models.dart';
import '../pages/sangong_user_detail_page.dart';
import '../support/sangong_ui.dart' show DioErrorMessage;
import 'sangong_authorized_view.dart';
import 'sangong_profile_ledger_frame.dart';
import 'diagnostics/sangong_profile_ledger_log.dart';

class SangongProfileLedger extends StatefulWidget {
  const SangongProfileLedger(
      {super.key, required this.userID, this.embedded = false});
  final String userID;
  final bool embedded;
  @override
  State<SangongProfileLedger> createState() => _SangongProfileLedgerState();
}

class _SangongProfileLedgerState extends State<SangongProfileLedger> {
  late final SangongRuntime _runtime = SangongScope.read(context);
  late Future<SangongAdminUserReport?> _request;
  @override
  void initState() {
    super.initState();
    _request = _load();
  }

  Future<SangongAdminUserReport?> _load() async {
    final target = widget.userID;
    final diagnostics = SangongProfileLedgerLog.start(_runtime.http, target);
    try {
      final report = await _runtime.admin.findUserReport(target);
      diagnostics?.complete(
          returnedUserID: report?.imUserId,
          current: mounted && widget.userID == target && _runtime.canManage);
      return report;
    } catch (error) {
      diagnostics?.failed(error);
      rethrow;
    }
  }

  Widget _status(String message, {String? detail, bool loading = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SangongProfileLedgerFrame(
      embedded: widget.embedded,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.s5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (loading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: AppTokens.s5),
            ],
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTokens.textPrimary(dark: dark))),
            if (detail != null) ...[
              const SizedBox(height: AppTokens.s3),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTokens.textSecondary(dark: dark))),
            ],
            if (!loading)
              TextButton(
                  onPressed: () => setState(() => _request = _load()),
                  child: const Text('重试')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SangongAuthorizedView(
      runtime: _runtime,
      child: FutureBuilder<SangongAdminUserReport?>(
          future: _request,
          builder: (context, result) {
            if (result.connectionState != ConnectionState.done) {
              return _status('正在加载游戏流水…', loading: true);
            }
            if (result.hasError) {
              return _status('游戏流水加载失败',
                  detail: DioErrorMessage.forApp(result.error!));
            }
            if (result.data == null) {
              return _status('暂未找到该用户的游戏账户');
            }
            if (result.data!.imUserId != widget.userID) {
              return _status('用户资料暂时无法确认，请重试');
            }
            return SangongUserDetailPage(user: result.data!);
          }));
}
