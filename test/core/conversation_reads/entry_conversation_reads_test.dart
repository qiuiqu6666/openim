import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/conversation_reads/conversation_batch_read_api.dart';
import 'package:openim/core/conversation_reads/entry_conversation_reads.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio previous;
  late EntryConversationReads reads;
  late List<Map> submissions;
  late List<String> acknowledged;
  EntryConversationReads create() => EntryConversationReads(
      isCurrent: () => true, changed: () {}, acknowledged: acknowledged.addAll);
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ConversationInfo row(int seq, int unread) => ConversationInfo(
      conversationID: 'sg_a',
      unreadCount: unread,
      latestMsg: Message(
          seq: seq, clientMsgID: 'm$seq', status: MessageStatus.succeeded));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'self';
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'imToken': 'self-token',
      'chatToken': 'chat-token'
    }));
    submissions = [];
    acknowledged = [];
    previous = http.dio;
    http.dio = Dio();
    http.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      submissions.add(Map.from(o.data as Map));
      h.resolve(Response(requestOptions: o, data: {
        'errCode': 0,
        'data': {
          'results': [
            for (final t in o.data['targets']) {...t as Map, 'success': true}
          ]
        }
      }));
    }));
    reads = create();
  });
  tearDown(() {
    reads.close();
    http.dio.close(force: true);
    http.dio = previous;
  });

  test(
      'persisted cutoff clears old badge, preserves new unread and survives restart',
      () async {
    await reads.enqueue(const BatchReadTarget('sg_a', 100));
    await settle();
    expect(submissions.single['targets'], [
      {'conversationID': 'sg_a', 'hasReadSeq': 100}
    ]);
    expect(acknowledged, ['sg_a']);
    final original = row(100, 90);
    expect(reads.project(original).unreadCount, 0);
    expect(original.unreadCount, 90,
        reason: 'never mutate SDK callback models');
    expect(reads.project(row(101, 91)).unreadCount, 1);
    expect(
        reads.project(row(100, 90), current: row(101, 1)).latestMsg?.seq, 101);
    expect(reads.project(row(100, 90), current: row(101, 1)).unreadCount, 1);
    expect(reads.project(row(105, 2)).unreadCount, 2);
    reads.close();
    reads = create();
    reads.queue.kick();
    await settle();
    expect(reads.project(row(100, 90)).unreadCount, 0);
    expect(submissions, hasLength(1));
  });

  test('pending work persists while offline and resumes with same target',
      () async {
    reads.queue.setForeground(false);
    await reads.enqueue(const BatchReadTarget('sg_a', 100));
    expect(submissions, isEmpty);
    expect(reads.project(row(100, 90)).unreadCount, 0);
    reads.close();
    reads = create();
    reads.queue.kick();
    await settle();
    expect(submissions.single['targets'][0]['hasReadSeq'], 100);
  });

  test('different account cannot inherit watermark or replay prior work',
      () async {
    reads.queue.setForeground(false);
    await reads.enqueue(const BatchReadTarget('sg_a', 100));
    reads.close();
    OpenIM.iMManager.userID = 'other';
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'other',
      'imToken': 'other-token',
      'chatToken': 'other-chat'
    }));
    reads = create();
    reads.queue.kick();
    await settle();
    expect(submissions, isEmpty);
    expect(reads.project(row(100, 90)).unreadCount, 90);
  });

  test('unknown or temporary preview and private messages keep original count',
      () async {
    reads.queue.setForeground(false);
    await reads.enqueue(const BatchReadTarget('sg_a', 100));
    expect(reads.project(row(0, 5)).unreadCount, 5);
    final temporary = row(100, 5);
    temporary.latestMsg!.status = MessageStatus.sending;
    expect(reads.project(temporary).unreadCount, 5);
    final private = row(100, 5)..isPrivateChat = true;
    expect(reads.project(private).unreadCount, 5);
  });
}
