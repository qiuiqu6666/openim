import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  test('voice, file and video summaries use SDK elements', () {
    expect(
        IMUtils.parseMsg(Message.fromJson({
          'contentType': MessageType.voice,
          'soundElem': {'duration': 30}
        })),
        '[${StrRes.voice}] 30″');
    expect(
        IMUtils.parseMsg(Message.fromJson({
          'contentType': MessageType.file,
          'fileElem': {'fileName': 'report.pdf'}
        })),
        '[${StrRes.file}] report.pdf');
    expect(
        IMUtils.parseMsg(Message.fromJson({'contentType': MessageType.video})),
        '[${StrRes.video}]');
    expect(
        IMUtils.parseMsg(Message.fromJson({'contentType': MessageType.voice})),
        '[${StrRes.voice}]');
    expect(
        IMUtils.parseMsg(Message.fromJson({'contentType': MessageType.file})),
        '[${StrRes.file}]');
  });
  test('call summaries match bubble protocol outcomes', () {
    for (final type in ['audio', 'video']) {
      for (final state in [
        'hangup',
        'beHangup',
        'cancel',
        'beCanceled',
        'reject',
        'beRejected',
        'timeout',
        'networkError'
      ]) {
        final message = Message.fromJson({
          'contentType': MessageType.custom,
          'customElem': {
            'data': jsonEncode({
              'customType': 901,
              'data': {'type': type, 'state': state, 'duration': 65}
            })
          }
        });
        final label = type == 'audio' ? StrRes.callVoice : StrRes.callVideo;
        expect(IMUtils.parseMsg(message, isConversation: true),
            '[$label] ${IMUtils.parseCustomMessage(message)['content']}');
      }
    }
  });
  test('unknown call states retain type without inventing an outcome', () {
    final message = Message.fromJson({
      'contentType': MessageType.custom,
      'customElem': {
        'data': jsonEncode({
          'customType': 901,
          'data': {'type': 'audio', 'state': 'future-state'}
        })
      }
    });
    expect(IMUtils.parseMsg(message), '[${StrRes.callVoice}]');
  });
  test('file names are flattened for single line previews', () {
    final message = Message.fromJson({
      'contentType': MessageType.file,
      'fileElem': {'fileName': 'long\nname.pdf'}
    });
    expect(IMUtils.parseMsg(message), '[${StrRes.file}] long name.pdf');
  });
}
