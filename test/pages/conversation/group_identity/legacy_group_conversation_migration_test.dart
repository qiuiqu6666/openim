import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/group_identity/legacy_group_conversation_migration.dart';
import 'package:openim/services/legacy_identity/legacy_group_identity.dart';
import 'package:openim/services/legacy_identity/legacy_server_snapshot.dart';

const gid = 'lg_4b41122c9b36f283ffa962265a4385a6';
const oldID = 'sg_$gid';
const newID = 'sg_@$gid';

class Fixture {
  LegacyCleanupSession session =
      (owner: 'owner', token: 'token', server: 'http://129.226.192.93:10002');
  bool active = true;
  final old = ConversationInfo(
      conversationID: oldID,
      groupID: gid,
      conversationType: ConversationType.superGroup,
      latestMsgSendTime: 100);
  final next = ConversationInfo(
      conversationID: newID,
      groupID: '@$gid',
      conversationType: ConversationType.superGroup,
      latestMsgSendTime: 100);
  late final rows = <ConversationInfo>[old, next];
  final hidden = <String>[];
  final notified = <String>[];
  final server = <String>{newID};
  final copied = <String>[];
  Future<AdvancedMessage> Function()? history;
  Future<Set<String>> Function()? snapshot;
  late final migration = LegacyGroupConversationMigration(
    session: () => session,
    serverIDs: (_) async => snapshot == null ? server : await snapshot!(),
    readPage: (offset, count) async => rows.skip(offset).take(count).toList(),
    readConversations: (ids) async =>
        rows.where((row) => ids.contains(row.conversationID)).toList(),
    readHistory: (_, __) async => history == null
        ? AdvancedMessage(
            messageList: [Message(clientMsgID: 'stable', seq: 1)], isEnd: true)
        : await history!(),
    setDraft: (id, text) async {
      copied.add(id);
      next.draftText = text;
    },
    hide: (id) async {
      hidden.add(id);
      old.latestMsgSendTime = 0;
      old.draftText = '';
    },
  );
  Future<void> run() => migration.run(
      isActive: () => active,
      onHidden: (row) => notified.add(row.conversationID));
}

void main() {
  test('canonical IDs retain the exact original hash and scope', () {
    const server = 'http://129.226.192.93:10002';
    expect(LegacyGroupIdentity.canonical(gid, server: server), '@$gid');
    expect(LegacyGroupIdentity.canonical('@$gid', server: server), '@$gid');
    expect(LegacyGroupIdentity.canonical(gid, server: 'https://other.example'),
        gid);
    expect(
        LegacyGroupIdentity.canonical('lg_other', server: server), 'lg_other');
  });

  test('hides only the replaced local conversation without deleting history',
      () async {
    final f = Fixture();
    await f.run();
    expect(f.hidden, [oldID]);
    expect(f.notified, [oldID]);
    await f.run();
    expect(f.hidden, [oldID]);
  });

  test('requires old ID absent and new ID present on server', () async {
    final f = Fixture()..server.add(oldID);
    await f.run();
    expect(f.hidden, isEmpty);
    f.server.clear();
    await f.run();
    expect(f.hidden, isEmpty);
  });

  test('waits for the SDK replacement before hiding old history', () async {
    final f = Fixture();
    f.rows.remove(f.next);
    await f.run();
    expect(f.hidden, isEmpty);
  });

  test('copies a draft then verifies it survived before hiding', () async {
    final f = Fixture();
    f.old.draftText = 'unfinished draft';
    await f.run();
    expect(f.next.draftText, 'unfinished draft');
    expect(f.copied, [newID]);
    expect(f.hidden, [oldID]);
  });

  test('conflicting drafts are both retained', () async {
    final f = Fixture();
    f.old.draftText = 'old draft';
    f.next.draftText = 'new draft';
    await f.run();
    expect(f.old.draftText, 'old draft');
    expect(f.next.draftText, 'new draft');
    expect(f.copied, isEmpty);
    expect(f.hidden, isEmpty);
  });

  test('new draft written while checking history wins', () async {
    final f = Fixture();
    f.old.draftText = 'old draft';
    f.history = () async {
      f.next.draftText = 'just typed';
      return AdvancedMessage(messageList: [], isEnd: true);
    };
    await f.run();
    expect(f.next.draftText, 'just typed');
    expect(f.hidden, isEmpty);
  });

  test('pending local messages and incomplete history remain visible',
      () async {
    final f = Fixture();
    f.history = () async => AdvancedMessage(
        messageList: [Message(clientMsgID: 'pending', seq: 0)], isEnd: true);
    await f.run();
    expect(f.hidden, isEmpty);
    f.history = () async => AdvancedMessage(messageList: [], isEnd: false);
    await f.run();
    expect(f.hidden, isEmpty);
    f.history = () async => AdvancedMessage(errCode: 1001, isEnd: true);
    await f.run();
    expect(f.hidden, isEmpty);
  });

  test('account switch during asynchronous lookup never mutates new account',
      () async {
    final f = Fixture();
    f.snapshot = () async {
      f.session =
          (owner: 'other', token: 'other-token', server: f.session.server);
      return {newID};
    };
    await f.run();
    expect(f.hidden, isEmpty);
    expect(f.copied, isEmpty);
  });

  test('closing controller while checking history cancels mutations', () async {
    final f = Fixture();
    final waiting = Completer<AdvancedMessage>();
    f.history = () => waiting.future;
    final run = f.run();
    await Future<void>.delayed(Duration.zero);
    f.active = false;
    waiting.complete(AdvancedMessage(messageList: [], isEnd: true));
    await run;
    expect(f.hidden, isEmpty);
  });

  test('server reintroducing old conversation cancels cleanup', () async {
    final f = Fixture();
    var calls = 0;
    f.snapshot = () async => ++calls == 1 ? {newID} : {oldID, newID};
    await f.run();
    expect(f.hidden, isEmpty);
  });
}
