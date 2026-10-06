import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/internal_transfer/data/fund_transfer_recipient_policy.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  test('reserved service IDs are excluded without profile metadata', () {
    for (final id in ['99Message', '99Pay', 'assistant']) {
      expect(FundTransferRecipientPolicy.allowsUser(userID: id), isFalse);
      expect(FundTransferRecipientPolicy.allowsUser(userID: ' $id '), isFalse);
      expect(
          FundTransferRecipientPolicy.allowsUser(
              userID: id, ex: '{"accountType":"user"}'),
          isFalse);
    }
  });

  test('official metadata excludes renamed and custom service identities', () {
    for (final extension in [
      '{"accountType":"official"}',
      '{"accountType":"official","officialRole":"message"}',
      '{"accountType":"official","officialRole":"pay"}',
      '{"accountType":"official","officialRole":"assistant"}',
      '{"accountType":"official","officialRole":"other-service"}',
    ]) {
      expect(
          FundTransferRecipientPolicy.allowsUser(
              userID: 'renamed-service', ex: extension),
          isFalse);
    }
  });

  test('malformed or unrelated metadata keeps ordinary recipients available',
      () {
    for (final extension in [
      null,
      '',
      ' ',
      'not-json',
      '{"accountType":',
      'null',
      '[]',
      '"official"',
      '{"accountType":"user","officialRole":"message"}',
      '{"officialRole":"pay"}',
      '{"accountType":true}',
    ]) {
      expect(
          FundTransferRecipientPolicy.allowsUser(
              userID: 'personal-user', ex: extension),
          isTrue,
          reason: 'Only verified identity metadata should hide a user.');
    }
  });

  test('ordinary friends sharing service names remain selectable', () {
    for (final name in ['99Message', '99Pay', 'AI助理', 'assistant']) {
      final friend = ISUserInfo.fromJson({
        'userID': 'personal-friend',
        'nickname': name,
        'remark': name,
      });
      final profile = UserFullInfo(userID: 'personal-friend', nickname: name);
      expect(
          FundTransferRecipientPolicy.allowsUser(
              userID: friend.userID, ex: friend.ex),
          isTrue);
      expect(
          FundTransferRecipientPolicy.allowsUser(
              userID: profile.userID, ex: profile.ex),
          isTrue);
    }
  });

  test('SDK friends and API profiles use the same official identity rule', () {
    final friend = ISUserInfo.fromJson({
      'userID': 'renamed-service',
      'nickname': '客户服务',
      'ex': '{"accountType":"official"}',
    });
    final profile = UserFullInfo(
        userID: 'renamed-service',
        nickname: '客户服务',
        ex: '{"accountType":"official"}');
    expect(
        FundTransferRecipientPolicy.allowsUser(
            userID: friend.userID, ex: friend.ex),
        isFalse);
    expect(
        FundTransferRecipientPolicy.allowsUser(
            userID: profile.userID, ex: profile.ex),
        isFalse);
  });

  test('a recipient must have a nonempty IM identity', () {
    for (final id in [null, '', ' ', '\n\t']) {
      expect(FundTransferRecipientPolicy.allowsUser(userID: id), isFalse);
    }
    expect(FundTransferRecipientPolicy.allowsUser(userID: ' im_personal '),
        isTrue);
  });
}
