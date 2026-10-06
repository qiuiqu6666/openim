import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/navigation/official_account_resolver.dart';

ConversationInfo _conversation({
  String userID = 'peer',
  int type = ConversationType.single,
  String? ex,
}) =>
    ConversationInfo(
        conversationID: 'si_peer_self',
        conversationType: type,
        userID: userID,
        ex: ex);

void main() {
  test('notification IDs and role metadata use the read-only conversation',
      () async {
    var lookups = 0;
    final resolver = OfficialAccountResolver(loadProfiles: (_) async {
      lookups++;
      throw StateError('Offline');
    });
    for (final id in ['99Message', '99Pay']) {
      final resolution =
          await resolver.resolveConversation(_conversation(userID: id));
      expect(resolution.target, OfficialConversationTarget.notification);
      expect(resolution.account!.userID, id);
      expect(resolution.account!.isPay, id == '99Pay');
    }
    final metadata = await resolver.resolveConversation(_conversation(
        userID: 'new-message-id',
        ex: '{"accountType":"official","officialRole":"message"}'));
    expect(metadata.target, OfficialConversationTarget.notification);
    expect(metadata.account!.isPay, isFalse);
    expect(lookups, 0);
  });

  test('profile role metadata selects only the requested notification account',
      () async {
    final resolver = OfficialAccountResolver(
        loadProfiles: (id) async => [
              PublicUserInfo(
                  userID: 'other',
                  ex: '{"accountType":"official","officialRole":"message"}'),
              PublicUserInfo(
                  userID: id,
                  ex: '{"accountType":"official","officialRole":"pay"}'),
            ]);
    final resolution = await resolver.resolveConversation(_conversation());
    expect(resolution.target, OfficialConversationTarget.notification);
    expect(resolution.account!.isPay, isTrue);
    expect(resolution.account!.userID, 'peer');
    final roleOnly = OfficialAccountResolver(
        loadProfiles: (id) async =>
            [PublicUserInfo(userID: id, ex: '{"officialRole":"pay"}')]);
    expect((await roleOnly.resolveConversation(_conversation())).target,
        OfficialConversationTarget.chat);
  });

  test('official metadata is strict JSON and never inferred from a name', () {
    expect(
        OfficialAccountResolver.isOfficialExtension(
            '{"accountType":"official"}'),
        isTrue);
    for (final ex in [
      null,
      '',
      '{',
      '[]',
      '"official"',
      '{"accountType":"Official"}',
      '{"accountType":true}',
      '{"nickname":"AI助理"}',
    ]) {
      expect(OfficialAccountResolver.isOfficialExtension(ex), isFalse,
          reason: '$ex');
    }
  });

  test('assistant and conversation official metadata need no profile lookup',
      () async {
    var lookups = 0;
    final resolver = OfficialAccountResolver(loadProfiles: (_) async {
      lookups++;
      return [];
    });
    expect(await resolver.usesOfficialPage(_conversation(userID: 'assistant')),
        isTrue);
    expect(
        await resolver
            .usesOfficialPage(_conversation(ex: '{"accountType":"official"}')),
        isTrue);
    expect(lookups, 0);
  });

  test('only single conversations with a recipient may use the official page',
      () async {
    var lookups = 0;
    final resolver = OfficialAccountResolver(loadProfiles: (_) async {
      lookups++;
      return [];
    });
    for (final conversation in [
      _conversation(userID: 'assistant', type: 2),
      _conversation(
          type: ConversationType.superGroup, ex: '{"accountType":"official"}'),
      _conversation(userID: ''),
    ]) {
      expect(await resolver.usesOfficialPage(conversation), isFalse);
    }
    expect(lookups, 0);
  });

  test('SDK user metadata resolves only the requested recipient', () async {
    final recipients = <String>[];
    final resolver = OfficialAccountResolver(loadProfiles: (id) async {
      recipients.add(id);
      return [
        PublicUserInfo(userID: 'other', ex: '{"accountType":"official"}'),
        PublicUserInfo(userID: id, ex: '{"accountType":"official"}'),
      ];
    });
    expect(await resolver.usesOfficialPage(_conversation()), isTrue);
    expect(recipients, ['peer']);
    final wrongUser = OfficialAccountResolver(
        loadProfiles: (_) async => [
              PublicUserInfo(userID: 'other', ex: '{"accountType":"official"}')
            ]);
    expect(await wrongUser.usesOfficialPage(_conversation()), isFalse);
  });

  test('malformed profile and SDK errors preserve ordinary chat routing',
      () async {
    final malformed = OfficialAccountResolver(
        loadProfiles: (id) async => [
              PublicUserInfo(userID: id, ex: '{'),
            ]);
    expect(await malformed.usesOfficialPage(_conversation(ex: '{')), isFalse);
    final unavailable = OfficialAccountResolver(
        loadProfiles: (_) => Future.error(StateError('SDK unavailable')));
    expect(await unavailable.usesOfficialPage(_conversation()), isFalse);
  });

  test('lookup is bounded and a late profile does not alter another lookup',
      () async {
    final delayed = Completer<List<PublicUserInfo>>();
    var lookups = 0;
    final resolver = OfficialAccountResolver(
        lookupTimeout: const Duration(milliseconds: 10),
        loadProfiles: (_) {
          lookups++;
          return lookups == 1 ? delayed.future : Future.value([]);
        });
    expect(await resolver.usesOfficialPage(_conversation()), isFalse);
    delayed.complete(
        [PublicUserInfo(userID: 'peer', ex: '{"accountType":"official"}')]);
    expect(await resolver.usesOfficialPage(_conversation()), isFalse);
    expect(lookups, 2);
  });
}
