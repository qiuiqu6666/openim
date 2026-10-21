import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  test('creation notification selects channel wording only for channel marker', () {
    for (final ex in [null, '', 'invalid', '{}', '{"conversationKind":"channel"}']) {
      final notification = GroupNotification.fromJson({
        'group': {'groupID': 'channel123', 'ex': ex},
      });
      expect(IMUtils.groupCreatedLabel(notification),
          ex == '{"conversationKind":"channel"}' ? StrRes.createChannelNtf : StrRes.createGroupNtf);
    }
  });
}
