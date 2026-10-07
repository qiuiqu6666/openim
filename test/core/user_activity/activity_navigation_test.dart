import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/user_activity/activity_runtime.dart';
import 'package:openim/core/user_activity/activity_sdk.dart';

class _RouteSink implements ActivityRuntime {
  final visits = <String?>[];
  @override
  void visitRoute(String? route) => visits.add(route);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('optional SDK observation preserves success and original exception',
      () async {
    expect(await observeUserActivity('group_invite', () async => 42), 42);
    final original = StateError('business failure');
    await expectLater(
        observeUserActivity<void>('group_join', () async => throw original),
        throwsA(same(original)));
  });
  testWidgets('page observer restores pages on pop and ignores dialogs',
      (tester) async {
    final sink = _RouteSink();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        navigatorObservers: [ActivityNavigationObserver(sink)],
        home: const Scaffold(body: Text('Home'))));
    key.currentState!.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/wallet_withdraw'),
        builder: (_) => const Scaffold(body: Text('Withdraw'))));
    await tester.pumpAndSettle();
    expect(sink.visits.last, '/wallet_withdraw');
    final count = sink.visits.length;
    showDialog<void>(
        context: key.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Confirm')));
    await tester.pumpAndSettle();
    expect(sink.visits.length, count);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(sink.visits.length, count);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(sink.visits.last, '/');
  });
}
