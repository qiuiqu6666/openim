import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/widgets/authorization/privilege_route_guard.dart';

import '../../sangong_test_support.dart';

class _PendingPrivilege extends FixtureAccountPrivilege {
  final result = Completer<bool>();
  @override
  Future<bool> refresh() => result.future;
}

void main() {
  testWidgets('group invalidation waits for initial account verification',
      (tester) async {
    final privilege = _PendingPrivilege();
    final scope = ValueNotifier(0);
    var current = true;
    var reads = 0;
    final featureContext = GroupFeatureContext(
      groupID: 'group-sangong',
      groupName: '三公',
      currentUserID: 'owner',
      api: SangongTestApi(),
      accountPrivilege: privilege,
      sessionCurrent: () => true,
      onFeaturesChanged: (_) {},
    );
    await tester.pumpWidget(MaterialApp(
      home: SangongPrivilegeRouteGuard(
        featureContext: featureContext,
        scopeChanges: scope,
        isCurrent: () => current,
        canRevalidate: () => true,
        revalidate: (active) async {
          reads++;
          current = true;
          return true;
        },
        builder: (_) => const Scaffold(body: Text('已授权的运营页面')),
      ),
    ));
    current = false;
    scope.value++;
    await tester.pump();
    expect(reads, 0);
    expect(find.text('已授权的运营页面'), findsNothing);
    privilege.result.complete(true);
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('已授权的运营页面'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    privilege.dispose();
    scope.dispose();
    expect(tester.takeException(), isNull);
  });
}
