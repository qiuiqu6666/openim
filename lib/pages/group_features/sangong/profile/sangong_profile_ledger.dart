import 'package:flutter/material.dart';
import '../sangong_scope.dart';
import '../models/sangong_admin_models.dart';
import '../pages/sangong_user_detail_page.dart';
import 'sangong_authorized_view.dart';

class SangongProfileLedger extends StatefulWidget {
  const SangongProfileLedger({super.key, required this.userID});
  final String userID;
  @override
  State<SangongProfileLedger> createState() => _SangongProfileLedgerState();
}

class _SangongProfileLedgerState extends State<SangongProfileLedger> {
  late final SangongRuntime _runtime = SangongScope.read(context);
  late Future<SangongAdminUserReport?> _request;
  @override
  void initState() {
    super.initState();
    _request = _runtime.admin.findUserReport(widget.userID);
  }

  @override
  Widget build(BuildContext context) => SangongAuthorizedView(
      runtime: _runtime,
      child: FutureBuilder<SangongAdminUserReport?>(
          future: _request,
          builder: (context, result) {
            if (result.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (result.hasError ||
                result.data == null ||
                result.data!.imUserId != widget.userID) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('未能读取该用户的游戏流水'),
                TextButton(
                    onPressed: () => setState(() => _request =
                        _runtime.admin.findUserReport(widget.userID)),
                    child: const Text('重试'))
              ]));
            }
            return SangongUserDetailPage(user: result.data!);
          }));
}
