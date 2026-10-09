import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/legacy_cleanup/legacy_service_conversation_cleanup.dart';

const _peer = 'im_5ff61c4e25466a7ff2ecd711c09c0702';
const _otherPeer = 'im_5882da9ecbe9a9e10cc9cc7c9be4fb72';
const _cutoff = LegacyServiceConversationCleanup.cutoffMilliseconds;

ConversationInfo _conversation({
  String owner = 'self',
  String peer = _peer,
  int? time = _cutoff,
}) {
  final pair = [owner, peer]..sort();
  return ConversationInfo(
    conversationID: 'si_${pair.join('_')}',
    conversationType: ConversationType.single,
    userID: peer,
    latestMsgSendTime: time,
  );
}

Map<String, dynamic> _response([List<String>? ids]) => {
      'errCode': 0,
      'data': {
        'versionID': 'server-version',
        // The real protobuf endpoint omits an empty conversationIDs list.
        if (ids != null) 'conversationIDs': ids,
      },
    };

class _Fixture {
  LegacyCleanupSession session = (
    owner: 'self',
    token: 'test-token',
    server: 'http://129.226.192.93:10002'
  );
  bool active = true;
  final rows = <ConversationInfo>[_conversation()];
  final deleted = <String>[];
  final deletedMessages = <String>[];
  final completed = <String>{};
  final notified = <String>[];
  final events = <String>[];
  final requests = <Map<String, dynamic>>[];
  Future<dynamic> Function()? reply;
  Future<List<ConversationInfo>> Function(String)? reread;
  Future<AdvancedMessage> Function(String, Message?)? history;
  Future<void> Function(String, String)? removeMessage;
  bool deleteFails = false;
  late final cleanup = LegacyServiceConversationCleanup(
    session: () => session,
    readPage: (offset, count) async {
      events.add('page:$offset');
      return rows.skip(offset).take(count).toList();
    },
    readConversation: (id) async => reread != null
        ? reread!(id)
        : rows.where((item) => item.conversationID == id).toList(),
    readHistory: (id, start) async => history != null
        ? await history!(id, start)
        : AdvancedMessage(messageList: [], isEnd: true),
    deleteMessage: (id, messageID) async {
      if (removeMessage != null) await removeMessage!(id, messageID);
      deletedMessages.add(messageID);
    },
    hideConversation: (id) async {
      events.add('delete');
      if (deleteFails) throw StateError('offline');
      deleted.add(id);
      rows.removeWhere((item) => item.conversationID == id);
    },
    post: (url, body, options) async {
      requests.add({'url': url, ...body, 'token': options.headers!['token']});
      return reply != null ? await reply!() : _response();
    },
    isCompleted: (key) async => completed.contains(key),
    markCompleted: (key) async => completed.add(key),
  );

  Future<void> run() => cleanup.run(
        isActive: () => active,
        onDeleted: (item) => notified.add(item.conversationID),
      );
}

void main() {
  test('missing server CID clears local once, using the current owner token',
      () async {
    final f = _Fixture();
    final id = f.rows.single.conversationID;
    await f.run();
    expect(f.deleted, [id]);
    expect(f.notified, [id]);
    expect(f.requests, hasLength(3));
    expect(f.requests.first['userID'], 'self');
    expect(f.requests.first['idHash'], 1);
    expect(f.requests.first['token'], 'test-token');
    expect(f.requests.first['url'], endsWith('/get_full_conversation_ids'));
    expect(f.completed.single,
        contains('${LegacyServiceConversationCleanup.epoch}|'));
    // A delayed old SDK snapshot cannot cause another delete after completion.
    f.rows.add(_conversation());
    await f.run();
    expect(f.deleted, [id]);
  });

  test('existing or recreated server conversation is preserved', () async {
    for (final recreate in [false, true]) {
      final f = _Fixture();
      var call = 0;
      f.reply = () async => (++call == 1 && recreate)
          ? _response()
          : _response([
              f.rows.single.conversationID,
            ]);
      await f.run();
      expect(f.deleted, isEmpty);
      expect(f.completed, isEmpty);
    }
  });

  test(
      'network errors, failed envelope, equal response and malformed IDs fail closed',
      () async {
    final responses = <dynamic>[
      null,
      {'errCode': 1001, 'data': {}},
      {'errCode': 0, 'data': {}},
      {
        'errCode': 0,
        'data': {'versionID': 'v', 'equal': true}
      },
      {
        'errCode': 0,
        'data': {'versionID': 'v', 'conversationIDs': 'wrong'}
      },
      {
        'errCode': 0,
        'data': {
          'versionID': 'v',
          'conversationIDs': [null]
        }
      },
    ];
    for (final response in responses) {
      final f = _Fixture();
      f.reply = () async {
        if (response == null) throw StateError('offline');
        return response;
      };
      await f.run();
      expect(f.deleted, isEmpty);
      expect(f.completed, isEmpty);
    }
  });

  test('unrelated official account, groups and forged CID are preserved',
      () async {
    final f = _Fixture();
    f.rows
      ..clear()
      ..addAll([
        _conversation(peer: '99Message'),
        _conversation()..conversationType = ConversationType.superGroup,
        _conversation()..groupID = 'group',
        _conversation()..conversationID = 'si_wrong_pair',
      ]);
    await f.run();
    expect(f.deleted, isEmpty);
    expect(f.requests, isEmpty);
  });

  test('the two legacy account owners also clean their reverse private chats',
      () async {
    final f = _Fixture();
    f.session = (owner: _peer, token: 'test-token', server: f.session.server);
    f.rows
      ..clear()
      ..add(_conversation(owner: _peer, peer: 'self'));
    await f.run();
    expect(f.deleted, hasLength(1));
  });

  test('future messages, drafts, pending sends and unknown age are preserved',
      () async {
    final examples = [
      _conversation(time: _cutoff + 1),
      _conversation(time: null),
      _conversation(time: 0),
      _conversation()..draftTextTime = _cutoff + 1,
      _conversation()..draftText = 'undated draft',
      _conversation()..latestMsg = Message(seq: 0, createTime: _cutoff - 1),
      _conversation()..latestMsg = Message(seq: 10, sendTime: _cutoff + 1),
      _conversation()..latestMsg = Message(seq: 10, createTime: _cutoff + 1),
    ];
    for (final item in examples) {
      final f = _Fixture();
      f.rows
        ..clear()
        ..add(item);
      await f.run();
      expect(f.deleted, isEmpty);
    }
  });

  test('a message arriving during server lookup wins over the old snapshot',
      () async {
    final f = _Fixture();
    f.reread = (_) async => [_conversation(time: _cutoff + 1)];
    await f.run();
    expect(f.deleted, isEmpty);
  });

  for (final change in ['owner', 'token', 'server', 'closed']) {
    test('session $change change while HTTP is pending prevents deletion',
        () async {
      final f = _Fixture();
      final pending = Completer<dynamic>();
      final started = Completer<void>();
      f.reply = () {
        started.complete();
        return pending.future;
      };
      final run = f.run();
      await started.future;
      switch (change) {
        case 'owner':
          f.session = (
            owner: 'other',
            token: f.session.token,
            server: f.session.server
          );
        case 'token':
          f.session =
              (owner: f.session.owner, token: 'new', server: f.session.server);
        case 'server':
          f.session = (
            owner: f.session.owner,
            token: f.session.token,
            server: 'http://other'
          );
        case 'closed':
          f.active = false;
      }
      pending.complete(_response());
      await run;
      expect(f.deleted, isEmpty);
      expect(f.completed, isEmpty);
    });
  }

  test('other hosts and malformed base URLs never read or delete local data',
      () async {
    for (final url in [
      'http://elsewhere:10002',
      'http://129.226.192.93.attacker',
      'http://user@129.226.192.93',
      'http://129.226.192.93?next=other',
    ]) {
      final f = _Fixture();
      f.session = (owner: 'self', token: 'test-token', server: url);
      await f.run();
      expect(f.events, isEmpty);
      expect(f.requests, isEmpty);
    }
  });

  test('all pages are read before deletion can shift the pagination offsets',
      () async {
    final f = _Fixture();
    f.rows.addAll(
        List.generate(399, (index) => _conversation(peer: 'ordinary-$index')));
    f.rows.add(_conversation(peer: _otherPeer));
    await f.run();
    expect(f.events, ['page:0', 'page:400', 'delete', 'delete']);
    expect(f.deleted, hasLength(2));
    expect(f.rows, hasLength(399));
  });

  test('failed SDK deletion is not acknowledged and retries on the next run',
      () async {
    final f = _Fixture()..deleteFails = true;
    await f.run();
    expect(f.completed, isEmpty);
    expect(f.notified, isEmpty);
    f.deleteFails = false;
    await f.run();
    expect(f.deleted, hasLength(1));
    expect(f.completed, hasLength(1));
  });

  test(
      'history snapshot is fully paged before exact old message IDs are removed',
      () async {
    final f = _Fixture();
    final calls = <String>[];
    final old1 = Message(clientMsgID: 'old1', seq: 1, sendTime: _cutoff - 2);
    final old2 = Message(clientMsgID: 'old2', seq: 2, sendTime: _cutoff - 1);
    f.history = (_, start) async {
      calls.add('read:${start?.clientMsgID}');
      return start == null
          ? AdvancedMessage(messageList: [old2], isEnd: false)
          : AdvancedMessage(messageList: [old1], isEnd: true);
    };
    f.removeMessage = (_, id) async => calls.add('delete:$id');
    await f.run();
    expect(calls, ['read:null', 'read:old2', 'delete:old2', 'delete:old1']);
    expect(f.deleted, hasLength(1));
  });

  test(
      'new and pending messages discovered in history are never deleted or hidden',
      () async {
    final f = _Fixture();
    f.history = (_, __) async => AdvancedMessage(isEnd: true, messageList: [
          Message(clientMsgID: 'old', seq: 1, sendTime: _cutoff),
          Message(clientMsgID: 'new', seq: 2, sendTime: _cutoff + 1),
          Message(clientMsgID: 'pending', seq: 0, sendTime: _cutoff),
          Message(clientMsgID: 'unknown-time', seq: 3),
        ]);
    await f.run();
    expect(f.deletedMessages, ['old']);
    expect(f.deleted, isEmpty);
    expect(f.completed, isEmpty);
  });

  test(
      'local message deletion failure cannot hide or acknowledge the conversation',
      () async {
    final f = _Fixture();
    f.history = (_, __) async => AdvancedMessage(isEnd: true, messageList: [
          Message(clientMsgID: 'old', seq: 1, sendTime: _cutoff),
        ]);
    f.removeMessage = (_, __) async => throw StateError('local DB failure');
    await f.run();
    expect(f.deleted, isEmpty);
    expect(f.completed, isEmpty);
  });

  test('new server conversation before hide preserves local visibility',
      () async {
    final f = _Fixture();
    var call = 0;
    f.reply = () async =>
        ++call < 3 ? _response() : _response([f.rows.single.conversationID]);
    await f.run();
    expect(f.deleted, isEmpty);
    expect(f.completed, isEmpty);
  });

  test(
      'session change after one exact message deletion stops the remaining writes',
      () async {
    final f = _Fixture();
    f.history = (_, __) async => AdvancedMessage(isEnd: true, messageList: [
          Message(clientMsgID: 'old1', seq: 1, sendTime: _cutoff),
          Message(clientMsgID: 'old2', seq: 2, sendTime: _cutoff),
        ]);
    f.removeMessage = (_, __) async => f.active = false;
    await f.run();
    expect(f.deletedMessages, ['old1']);
    expect(f.deleted, isEmpty);
    expect(f.completed, isEmpty);
  });
}
