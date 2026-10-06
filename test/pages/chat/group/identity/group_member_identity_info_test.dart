import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity.dart';

void main() {
  test('member account remains separate from every supported SDK user ID', () {
    for (final id in ['im_random_123', '2138014845', 'm00000001']) {
      final member = GroupMemberIdentityInfo.fromJson({
        'groupID': 'group',
        'userID': id,
        'nickname': 'Member',
        'roleLevel': 60,
        'account': '0012345678',
      });
      expect(member, isA<GroupMembersInfo>());
      expect(member.userID, id);
      expect(member.account, '0012345678');
      expect(member.toJson()['userID'], id);
      expect(member.toJson()['account'], '0012345678');
      expect(member.toJson()['roleLevel'], 60);
    }
  });

  for (final entry in <String, Object?>{
    'missing': null,
    'null': null,
    'empty': '',
    'whitespace': '  ',
    'numeric': 1234567890,
  }.entries) {
    test('${entry.key} account remains absent on serialization', () {
      final member = GroupMemberIdentityInfo.fromJson({
        'userID': 'im_member',
        if (entry.key != 'missing') 'account': entry.value,
      });
      expect(member.account, isNull);
      expect(member.toJson().containsKey('account'), isFalse);
      expect(member.userID, 'im_member');
    });
  }

  test('accounts are opaque optional strings, without ten-digit coercion', () {
    final member = GroupMemberIdentityInfo.fromJson({
      'userID': 'im_member',
      'account': '@abcdefgh12',
    });
    expect(member.account, '@abcdefgh12');
    member.account = '';
    expect(member.toJson().containsKey('account'), isFalse);
    member.account = '0023456789';
    expect(member.toJson()['account'], '0023456789');
    member.account = null;
    expect(member.toJson().containsKey('account'), isFalse);
  });

  test('incremental insert and update preserve server account omission', () {
    final result = GroupMemberIdentityIncremental.fromJson({
      'version': '18',
      'versionID': 'version-a',
      'full': false,
      'delete': ['im_deleted'],
      'insert': [
        {'groupID': 'g', 'userID': 'im_insert', 'account': '0012345678'},
      ],
      'update': [
        {'groupID': 'g', 'userID': 'im_updated', 'roleLevel': 20},
      ],
      'group': {'groupID': 'g', 'lookMemberInfo': 1},
      'sortVersion': '9',
    });
    expect(result.version, 18);
    expect(result.versionID, 'version-a');
    expect(result.full, isFalse);
    expect(result.delete, ['im_deleted']);
    expect(result.insert.single.account, '0012345678');
    expect(result.update.single.account, isNull);
    expect(result.update.single.toJson().containsKey('account'), isFalse);
    expect(result.group?.lookMemberInfo, 1);
    expect(result.sortVersion, 9);
  });

  test('null protobuf arrays mean empty changes', () {
    final result = GroupMemberIdentityIncremental.fromJson({
      'full': true,
      'insert': null,
      'update': null,
      'delete': null,
    });
    expect(result.full, isTrue);
    expect(result.insert, isEmpty);
    expect(result.update, isEmpty);
    expect(result.delete, isEmpty);
    expect(result.group, isNull);
  });

  test('malformed members, versions and deletions fail parsing', () {
    expect(() => parseGroupMemberIdentities({}), throwsFormatException);
    expect(() => parseGroupMemberIdentities([123]), throwsFormatException);
    expect(() => GroupMemberIdentityIncremental.fromJson({'version': -1}),
        throwsFormatException);
    expect(
        () => GroupMemberIdentityIncremental.fromJson({
              'delete': [123]
            }),
        throwsFormatException);
  });
}
