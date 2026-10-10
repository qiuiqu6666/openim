import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/agents/data/sangong_agent_management_api.dart';
import '../sangong_test_support.dart';

void main() {
  testWidgets('user group reads by IM identity and saves or clears independently',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final management = SangongAgentManagementApi(runtime.http);
    api.respond = (call) => call.method == 'GET'
        ? {'agentGroupId': 'agents-B'}
        : sangongReceipt(call, {'agentGroupId': 'agents-B'});
    expect(await completeSangongRequest(tester,
        management.userAgentGroup('im_target')), 'agents-B');
    await completeSangongRequest(tester,
        management.setUserAgentGroup('im_target', 'agents-B'));
    await completeSangongRequest(tester,
        management.setUserAgentGroup('im_target', ''));
    final writes = api.calls.where((c) => c.method == 'POST').toList();
    expect(writes.length, 2);
    expect(writes.first.path, endsWith('/commands/user.agent_group'));
    expect(writes.first.body!['input'],
        {'imUserId': 'im_target', 'agentGroupId': 'agents-B'});
    expect(writes.last.body!['input'],
        {'imUserId': 'im_target', 'agentGroupId': ''});
    expect(writes.first.body!['requestId'],
        isNot(writes.last.body!['requestId']));
    api.respond = (_) => null;
    expect(await completeSangongRequest(tester,
        management.userAgentGroup('im_target')), isNull);
  });
}
