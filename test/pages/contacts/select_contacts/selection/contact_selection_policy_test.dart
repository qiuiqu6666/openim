import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/select_contacts/contact_card/contact_card_friend_directory.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/selection/contact_selection_policy.dart';
import 'package:openim_common/openim_common.dart';

const _messageExtension = '{"accountType":"official","officialRole":"message"}';
const _payExtension = '{"accountType":"official","officialRole":"pay"}';

ISUserInfo _friend(String id, {String? ex, String? nickname}) =>
    ISUserInfo.fromJson({
      'userID': id,
      'nickname': nickname ?? id,
      'tagIndex': 'A',
      'ex': ex,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stable notification IDs are blocked for every user projection', () {
    for (final id in ['99Message', '99Pay']) {
      final projections = <Object>[
        UserInfo(userID: id),
        FriendInfo(userID: id),
        PublicUserInfo(userID: id),
        UserFullInfo(userID: id),
        _friend(id),
        ConversationInfo(
          conversationID: 'si_${id}_self',
          conversationType: ConversationType.single,
          userID: id,
        ),
      ];
      expect(projections.where(ContactSelectionPolicy.allows), isEmpty);
      expect(ContactSelectionPolicy.allowsUserID(id), isFalse);
    }
  });

  test('strict notification roles are blocked without hiding AI assistants',
      () {
    for (final extension in [_messageExtension, _payExtension]) {
      expect(
          ContactSelectionPolicy.allows(
              FriendInfo(userID: 'notice', ex: extension)),
          isFalse);
      expect(
          ContactSelectionPolicy.allows(ConversationInfo(
              conversationID: 'si_notice_self',
              conversationType: ConversationType.single,
              userID: 'notice',
              ex: extension)),
          isFalse);
    }
    for (final extension in [
      null,
      'not-json',
      '{"officialRole":"pay"}',
      '{"accountType":"user","officialRole":"message"}',
      '{"accountType":"official"}',
      '{"accountType":"official","officialRole":"assistant"}',
    ]) {
      expect(
          ContactSelectionPolicy.allows(
              _friend('assistant', ex: extension, nickname: '99Pay')),
          isTrue);
    }
  });

  test('group IDs and group metadata do not acquire user restrictions', () {
    expect(
        ContactSelectionPolicy.allows(
            GroupInfo(groupID: '99Pay', ex: _payExtension)),
        isTrue);
    expect(
        ContactSelectionPolicy.allows(ConversationInfo(
            conversationID: 'sg_99Message',
            conversationType: ConversationType.superGroup,
            groupID: '99Message',
            ex: _messageExtension)),
        isTrue);
  });

  test('only forward/share destinations show notification identities', () {
    final notifications = [
      _friend('99Message'),
      _friend('99Pay'),
      _friend('notice', ex: _messageExtension),
      ConversationInfo(
          conversationID: 'si_another-notice_self',
          conversationType: ConversationType.single,
          userID: 'another-notice',
          ex: _payExtension),
    ];
    for (final action in SelAction.values) {
      final logic = SelectContactsLogic()..action = action;
      addTearDown(logic.onClose);
      for (final info in notifications) {
        expect(logic.isVisible(info), action == SelAction.forward);
        expect(ContactSelectionPolicy.allows(info), isFalse);
        expect(logic.onTap(info), isNull);
        logic.toggleChecked(info);
      }
      expect(logic.checkedList, isEmpty);
      expect(logic.enabledConfirmButton, isFalse);
      expect(logic.isVisible(_friend('ordinary', nickname: '99Pay')), isTrue);
      expect(
          logic.isVisible(
              _friend('assistant', ex: '{"accountType":"official"}')),
          action != SelAction.crateGroup && action != SelAction.addMember);
    }
  });

  test('picker badges follow account JSON rather than names or group metadata',
      () {
    expect(
        ContactSelectionPolicy.hasVerifiedIdentity(_friend('99Pay')), isTrue);
    expect(
        ContactSelectionPolicy.hasVerifiedIdentity(
            _friend('notice', ex: _messageExtension)),
        isTrue);
    expect(
        ContactSelectionPolicy.hasVerifiedIdentity(_friend('assistant',
            ex: '{"accountType":"official","officialRole":"assistant"}')),
        isTrue);
    expect(
        ContactSelectionPolicy.hasVerifiedIdentity(
            _friend('ordinary', nickname: '99Pay')),
        isFalse);
    expect(
        ContactSelectionPolicy.hasVerifiedIdentity(
            _friend('ordinary', ex: '{"officialRole":"pay"}')),
        isFalse);
    expect(
        ContactSelectionPolicy.hasVerifiedIdentity(
            GroupInfo(groupID: '99Pay', ex: _payExtension)),
        isFalse);
    expect(
        ContactSelectionPolicy.hasVerifiedIdentity(ConversationInfo(
            conversationID: 'sg_99Message',
            conversationType: ConversationType.superGroup,
            groupID: '99Message',
            ex: _messageExtension)),
        isFalse);
  });

  test('contact card directory hides notification roles and keeps its source',
      () {
    final source = [
      _friend('99Message'),
      _friend('99Pay'),
      _friend('notice', ex: _payExtension),
      _friend('assistant', ex: '{"accountType":"official"}'),
      _friend('friend', nickname: '99Message'),
    ];
    source.first.isShowSuspension = true;
    final originalFlags =
        source.map((friend) => friend.isShowSuspension).toList();
    final directory = buildContactCardFriendDirectory(source,
        starredAt: {'99Message': 2, 'assistant': 1});
    expect(directory.map((friend) => friend.userID), ['assistant', 'friend']);
    expect(buildContactCardFriendDirectory(source, query: '99Pay'), isEmpty);
    expect(source, hasLength(5));
    expect(source.map((friend) => friend.isShowSuspension), originalFlags);
  });

  test('controller refuses notification selection for every selection action',
      () async {
    for (final action in SelAction.values) {
      final logic = SelectContactsLogic()..action = action;
      addTearDown(logic.onClose);
      for (final blocked in [
        _friend('99Message'),
        _friend('99Pay'),
        _friend('notice', ex: _messageExtension),
      ]) {
        expect(logic.onTap(blocked), isNull);
        logic.toggleChecked(blocked);
        await logic.confirmSelectedItem(blocked);
      }
      expect(logic.checkedList, isEmpty);
      logic.checkedList['99Pay'] = _friend('99Pay');
      expect(logic.enabledConfirmButton, isFalse);
      expect(logic.isChecked(logic.checkedList['99Pay']), isFalse);
    }
  });

  test('group member policy blocks assistant and official user projections',
      () {
    for (final (id, extension) in [
      ('assistant', null),
      ('renamed-assistant', '{"accountType":"official"}'),
      ('service', '{"accountType":"official","officialRole":"assistant"}'),
      ('99Message', null),
      ('99Pay', null),
    ]) {
      final json = {'userID': id, 'nickname': 'AI助理', 'ex': extension};
      final projections = <Object>[
        UserInfo.fromJson(json),
        FriendInfo.fromJson(json),
        PublicUserInfo.fromJson(json),
        UserFullInfo.fromJson(json),
        GroupMembersInfo.fromJson(json),
        _friend(id, ex: extension, nickname: 'AI助理'),
        ConversationInfo(
            conversationID: 'si_${id}_self',
            conversationType: ConversationType.single,
            userID: id,
            ex: extension),
      ];
      expect(
          projections.where(ContactSelectionPolicy.allowsGroupMember), isEmpty,
          reason: '$id must not be available through another SDK projection.');
    }
    for (final id in ['assistant', ' assistant ', '99Message', '99Pay']) {
      expect(ContactSelectionPolicy.allowsGroupMemberUserID(id), isFalse);
    }
    expect(ContactSelectionPolicy.allowsGroupMemberUserID('ordinary'), isTrue);
  });

  test('group member policy keeps personal names and nonofficial metadata', () {
    for (final extension in [
      null,
      'not-json',
      '{"officialRole":"assistant"}',
      '{"accountType":"user","officialRole":"assistant"}',
    ]) {
      expect(
          ContactSelectionPolicy.allowsGroupMember(
              _friend('ordinary', ex: extension, nickname: 'AI助理')),
          isTrue);
    }
    for (final id in ['assistant', '99Pay']) {
      expect(
          ContactSelectionPolicy.allowsGroupMember(
              GroupInfo(groupID: id, ex: '{"accountType":"official"}')),
          isTrue);
      expect(
          ContactSelectionPolicy.allowsGroupMember(ConversationInfo(
              conversationID: 'sg_$id',
              conversationType: ConversationType.superGroup,
              groupID: id,
              ex: '{"accountType":"official"}')),
          isTrue);
    }
  });

  test('assistant selection is limited only by group member actions', () {
    final assistant = _friend('assistant',
        nickname: 'AI助理',
        ex: '{"accountType":"official","officialRole":"assistant"}');
    final service =
        _friend('official-service', ex: '{"accountType":"official"}');
    for (final action in SelAction.values) {
      final logic = SelectContactsLogic()..action = action;
      addTearDown(logic.onClose);
      final allows =
          action != SelAction.crateGroup && action != SelAction.addMember;
      expect(logic.allowsUserID('assistant'), allows);
      for (final info in [assistant, service]) {
        expect(logic.isVisible(info), allows);
        expect(logic.allowsSelection(info), allows);
        expect(logic.onTap(info), allows ? isNotNull : isNull);
        logic.checkedList[info.userID!] = info;
        expect(logic.isChecked(info), allows);
      }
      expect(logic.enabledConfirmButton, allows);
      expect(logic.isVisible(_friend('ordinary', nickname: 'AI助理')), isTrue);
      expect(logic.onTap(_friend('ordinary', nickname: 'AI助理')), isNotNull);
    }
  });

  test('a notification account cannot be recommended as a shared contact',
      () async {
    final logic = SelectContactsLogic()
      ..action = SelAction.recommend
      ..sharedContact = UserInfo(userID: '99Pay');
    addTearDown(logic.onClose);
    logic.toggleChecked(_friend('friend'));
    expect(logic.checkedList.keys, ['friend']);
    expect(logic.enabledConfirmButton, isFalse);
    await logic.confirmSelectedList();
    expect(logic.checkedList.keys, ['friend']);
  });
}
