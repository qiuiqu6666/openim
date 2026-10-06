import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/official_account/models/official_account.dart';

void main() {
  test('server IDs retain notification identity without profile metadata', () {
    for (final ex in [null, '', '{', '{"officialRole":"pay"}']) {
      final message = OfficialAccount.from(userID: '99Message', ex: ex)!;
      expect(message.userID, '99Message');
      expect(message.displayName, '99Message');
      expect(message.isPay, isFalse);
      final pay = OfficialAccount.from(userID: '99Pay', ex: ex)!;
      expect(pay.displayName, '99Pay');
      expect(pay.isPay, isTrue);
    }
    expect(
        OfficialAccount.from(
                userID: '99Message',
                ex: '{"accountType":"official","officialRole":"pay"}')!
            .isPay,
        isFalse);
  });

  test('SDK metadata requires both the official type and a notification role',
      () {
    expect(
        OfficialAccount.from(
                userID: 'notice',
                ex: '{"accountType":"official","officialRole":"message"}')!
            .role,
        OfficialAccountRole.message);
    expect(
        OfficialAccount.from(
                userID: 'pay',
                ex: '{"accountType":"official","officialRole":"pay"}')!
            .role,
        OfficialAccountRole.pay);
    for (final ex in [
      null,
      '',
      '{',
      '[]',
      '{"officialRole":"pay"}',
      '{"accountType":"user","officialRole":"pay"}',
      '{"accountType":"Official","officialRole":"pay"}',
      '{"accountType":"official"}',
      '{"accountType":"official","officialRole":"assistant"}',
    ]) {
      expect(OfficialAccount.from(userID: 'peer', ex: ex), isNull,
          reason: '$ex');
    }
    expect(
        OfficialAccount.from(
            userID: '', ex: '{"accountType":"official","officialRole":"pay"}'),
        isNull);
    expect(OfficialAccount.from(userID: '99pay'), isNull);
  });

  test('stable assistant identity is verified without becoming a notification',
      () {
    expect(OfficialAccount.assistantUserID, 'assistant');
    for (final ex in [
      null,
      '',
      '{broken',
      '[]',
      '{"accountType":"user"}',
      '{"accountType":"official","officialRole":"assistant"}',
    ]) {
      expect(
          OfficialAccount.hasVerifiedIdentity(
              userID: OfficialAccount.assistantUserID, ex: ex),
          isTrue,
          reason: 'The stable assistant ID remains verified with $ex.');
      expect(
          OfficialAccount.from(userID: OfficialAccount.assistantUserID, ex: ex),
          isNull,
          reason:
              'Verification does not give the assistant a notification role.');
    }
    expect(OfficialAccount.hasVerifiedIdentity(userID: ' assistant '), isTrue);
    expect(OfficialAccount.hasVerifiedIdentity(userID: 'ordinary'), isFalse);
    expect(OfficialAccount.hasVerifiedIdentity(userID: 'Assistant'), isFalse);
  });
}
