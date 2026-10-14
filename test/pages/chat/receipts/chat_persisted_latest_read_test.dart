import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/receipts/chat_persisted_latest_read.dart';

void main() {
  Message latest(
          {String id = 'latest',
          int seq = 713,
          int status = MessageStatus.succeeded}) =>
      Message.fromJson({
        'clientMsgID': id,
        'seq': seq,
        'status': status,
        'contentType': MessageType.text,
      });

  test('only the same persisted SDK latest can relax the loading gate', () {
    final preview = latest();
    final info =
        ConversationInfo(conversationID: 'sg_group', latestMsg: preview);
    expect(canReadPersistedLatestDuringLoad(info, latest()), isTrue);
    expect(canReadPersistedLatestDuringLoad(info, null), isFalse);
    expect(
        canReadPersistedLatestDuringLoad(info, latest(id: 'older')), isFalse);
    expect(canReadPersistedLatestDuringLoad(info, latest(seq: 712)), isFalse);
    expect(
        canReadPersistedLatestDuringLoad(
            info, latest(status: MessageStatus.sending)),
        isFalse);
    preview.seq = 0;
    expect(canReadPersistedLatestDuringLoad(info, latest(seq: 0)), isFalse);
  });

  test('private content and unconfirmed preview retain the loading barrier',
      () {
    final preview = latest();
    final info =
        ConversationInfo(conversationID: 'sg_group', latestMsg: preview);
    info.isPrivateChat = true;
    expect(canReadPersistedLatestDuringLoad(info, latest()), isFalse);
    info.isPrivateChat = false;
    preview.status = MessageStatus.sending;
    expect(canReadPersistedLatestDuringLoad(info, latest()), isFalse);
  });
}
