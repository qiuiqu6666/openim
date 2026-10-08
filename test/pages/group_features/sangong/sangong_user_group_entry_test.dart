import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_user_group_entry.dart';
import 'sangong_test_support.dart';

void main() {
  for (final group in ['A组', '0']) {
    testWidgets('saves points group $group through scoped command',
        (tester) async {
      var changed = 0;
      final api = SangongTestApi()
        ..respond = (call) {
          if (call.path.endsWith('/commands/user.group')) {
            expect(
                call.body?['input'], {'imUserId': 'im_target', 'group': group});
            return sangongReceipt(call, {
              'balance': 1000,
              'group': {'name': group == '0' ? '' : group}
            });
          }
          return sangongFixtureResponse(call);
        };
      final runtime = sangongTestRuntime(sangongTestContext(api));
      await pumpSangongPage(
          tester,
          runtime,
          Scaffold(
              body: SangongUserGroupEntry(
                  imUserId: 'im_target',
                  groupName: '',
                  onChanged: () => changed++)));
      await tester.tap(find.text('积分分组'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byType(CupertinoTextField), group);
      await tester.tap(find.text('保存'));
      await flushSangong(tester);
      expect(api.count('/commands/user.group'), 1);
      expect(changed, 1);
      expect(tester.takeException(), isNull);
      await unmountSangong(tester);
      runtime.dispose();
    });
  }
}
