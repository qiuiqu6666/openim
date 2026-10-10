import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim/services/chat_revocation_notice.dart';

void main() {
  tearDown(ChatHistoryCache.clear);

  Message original() => Message(
      clientMsgID: 'm1',
      sendTime: 1000,
      seq: 12,
      contentType: MessageType.text,
      textElem: TextElem(content: 'private original content'));

  test('recall replaces content while preserving position and identity', () {
    final notice = ChatRevocationNotice.replace(
        original(),
        RevokedInfo(
            clientMsgID: 'm1', revokerID: 'self', revokerNickname: '秋'));
    expect(notice.clientMsgID, 'm1');
    expect(notice.sendTime, 1000);
    expect(notice.seq, 12);
    expect(notice.textElem, isNull);
    expect(ChatRevocationNotice.text(notice, 'self'), '你撤回了一条消息');
    expect(ChatRevocationNotice.text(notice, 'other'), '秋撤回了一条消息');
  });

  test(
      'SDK recall covers cached and late history without leaking across accounts',
      () {
    ChatHistoryCache.write('self', 'c1', [original()]);
    ChatHistoryCache.revokeMessage(
        'self',
        RevokedInfo(
            clientMsgID: 'm1', revokerID: 'other', revokerNickname: '秋'));
    final cached = ChatHistoryCache.read('self', 'c1').single;
    expect(cached.contentType, MessageType.revokeMessageNotification);
    expect(ChatHistoryCache.isRemoved('self', 'm1'), isFalse);
    expect(
        ChatHistoryCache.applyRevocation('self', original()).textElem, isNull);
    expect(ChatHistoryCache.applyRevocation('another', original()).textElem,
        isNotNull);
    ChatHistoryCache.removeMessage('self', 'm1');
    expect(ChatHistoryCache.read('self', 'c1'), isEmpty);
  });

  test('missing or malformed names use a safe generic notice', () {
    expect(
        ChatRevocationNotice.text(
            ChatRevocationNotice.replace(original(), RevokedInfo()), 'self'),
        '一条消息已被撤回');
    expect(ChatRevocationNotice.text(Message(), 'self'), '一条消息已被撤回');
  });

  test('system admin operation names display as administrator', () {
    final notice = ChatRevocationNotice.replace(original(),
        RevokedInfo(revokerID: 'imAdmin', revokerNickname: 'imAdmin'));
    expect(ChatRevocationNotice.text(notice, 'self'), '管理员撤回了一条消息');
  });
}
