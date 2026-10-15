import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/mark_six/agent/data/agent_query_controller.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_repository.dart';
import '../../mark_six_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'same query retains results on refresh and failure; new query clears them',
      () async {
    final api = MarkSixFakeApi(
        respond: (_, __, ___, ____) => {
              'rows': [1]
            });
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentQueryController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    await state.load('/test', query: {'date': 'one'});
    final retained = state.data;
    expect(retained, isNotNull);
    final pending = Completer<Map<String, dynamic>>();
    api.respond = (_, __, ___, ____) => pending.future;
    final refresh = state.load('/test', query: {'date': 'one'}, force: true);
    expect(state.data, same(retained));
    pending.completeError(StateError('offline'));
    await refresh;
    expect(state.data, same(retained));
    expect(state.error, isNotNull);
    api.respond = (_, __, ___, ____) => {
          'rows': [2]
        };
    final next = state.load('/test', query: {'date': 'two'});
    expect(state.data, isNull);
    await next;
    expect(state.data, isNot(retained));
  });
}
