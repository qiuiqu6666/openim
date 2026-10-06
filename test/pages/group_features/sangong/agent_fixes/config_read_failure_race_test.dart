import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

void main() {
  testWidgets(
      'a superseded failed config read returns a newer save in the same scope',
      (tester) async {
    final reply = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => reply.future;
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final pending = runtime.config.refreshFromNetwork();
    await flushSangong(tester);
    await runtime.config
        .applySaved(SangongMyConfig.fromJson(sangongConfig(name: '已保存的新配置')));
    final task = completeSangongRequest(tester, pending);
    reply.completeError(StateError('superseded read'));
    final value = await task;
    expect(value.name, '已保存的新配置');
    expect(runtime.config.config.name, '已保存的新配置');
    expect(api.count('/my-config'), 1);
  });

  for (final invalidation in ['context', 'authorization']) {
    testWidgets(
        'a failed config read cannot use cache after $invalidation changes',
        (tester) async {
      var current = true;
      final reply = Completer<dynamic>();
      final api = SangongTestApi()..respond = (_) => reply.future;
      final runtime =
          SangongRuntime(sangongTestContext(api, current: () => current));
      addTearDown(runtime.dispose);
      final pending = runtime.config.refreshFromNetwork();
      await flushSangong(tester);
      await runtime.config
          .applySaved(SangongMyConfig.fromJson(sangongConfig(name: '旧配置')));
      if (invalidation == 'context') {
        runtime.updateContext(sangongTestContext(api, capabilityVersion: 2));
        expect(runtime.config.hasCachedConfig, isFalse);
      } else {
        current = false;
      }
      final expectation = expectLater(pending, throwsA(isA<Object>()));
      reply.completeError(StateError('old scope read'));
      await flushSangong(tester);
      await expectation;
      expect(api.count('/my-config'), 1);
    });
  }
}
