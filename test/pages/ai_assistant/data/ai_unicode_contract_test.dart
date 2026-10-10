import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/composer/ai_assistant_capability.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_contract.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_stream_client.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_transport.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_upload_mime.dart';
import 'package:openim/pages/ai_assistant/protocol/ai_openim_payload.dart';

import '../../../support/unicode/unicode_samples.dart';

class _FragmentedUnicodeResponse implements HttpClientAdapter {
  _FragmentedUnicodeResponse(this.body);
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody(
        Stream<Uint8List>.fromIterable(
            utf8.encode(body).map((byte) => Uint8List.fromList([byte]))),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final sample in unicodeSamples) {
    test('${sample.name}: AI input and returned text retain raw edge sequences',
        () {
      final text = ' ${sample.text}  ';
      final plan = AiAssistantSendPlanner.plan(
          tool: null, text: text, cards: [], files: []) as AiAssistantSendPlan;
      expect(plan.content.codeUnits, orderedEquals(text.codeUnits));
      expect(plan.displayText, text);
      expect((jsonDecode(AiOpenimPayload.image(text)) as Map)['prompt'], text);

      final history = AiAssistantHistoryItem.fromJson({
        'id': ' history-id ',
        'role': ' assistant ',
        'content': text,
      });
      expect(history.id, 'history-id');
      expect(history.role, 'assistant');
      expect(history.content.codeUnits, orderedEquals(text.codeUnits));
      final uploaded = AiAssistantUploadedFile.fromJson({
        'fileId': ' file-id ',
        'contentType': ' text/plain ',
        'fileName': text,
      });
      expect(uploaded.fileId, 'file-id');
      expect(uploaded.contentType, 'text/plain');
      expect(uploaded.fileName.codeUnits, orderedEquals(text.codeUnits));
      expect(AiAssistantUploadMime.ensureFileName('$text.png', 'image/png'),
          '$text.png');
      final delta =
          AiAssistantStreamEvent.parse('delta', jsonEncode({'text': text}));
      expect(delta?.text.codeUnits, orderedEquals(text.codeUnits));
      final error = AiAssistantStreamEvent.parse(
          'error', jsonEncode({'code': ' code ', 'message': text}));
      expect(error?.code, 'code');
      expect(error?.message.codeUnits, orderedEquals(text.codeUnits));
      final failure = AiAssistantTransport()
          .failure({'errCode': 'INPUT_REJECTED', 'errMsg': text}, 400);
      expect(failure.message.codeUnits, orderedEquals(text.codeUnits));
      final pasted = AiAssistantAnalyze.paste(text).toJson();
      expect((jsonDecode(jsonEncode(pasted)) as Map)['text'], text);
    });
  }

  test('AI content limit counts grapheme clusters without splitting a sequence',
      () {
    final family =
        unicodeSamples.firstWhere((sample) => sample.name == 'family');
    final accepted = family.text * 8000;
    final plan = AiAssistantSendPlanner.plan(
        tool: null,
        text: accepted,
        cards: [],
        files: []) as AiAssistantSendPlan;
    expect(plan.content, accepted);
    expect(
        AiAssistantSendPlanner.plan(
            tool: null, text: '${accepted}x', cards: [], files: []),
        isA<AiAssistantSendError>());
    final errorText = family.text * 200;
    final transport = AiAssistantTransport(dio: Dio());
    expect(transport.failure({'message': errorText}, 400).message, errorText);
  });

  test('blank validation does not mutate a whitespace base with combining mark',
      () {
    expect(
        AiAssistantSendPlanner.plan(
            tool: null, text: ' \n\t ', cards: [], files: []),
        isA<AiAssistantSendError>());
    final plan = AiAssistantSendPlanner.plan(
        tool: null,
        text: ' \u0301 ',
        cards: [],
        files: []) as AiAssistantSendPlan;
    expect(plan.content, ' \u0301 ');
    expect(plan.displayText, ' \u0301 ');
  });

  test('UTF-8 stream retains sequences across every possible byte boundary',
      () async {
    final text = unicodeSamples.map((sample) => sample.text).join(' / ');
    final event = jsonEncode({'text': ' $text '});
    final dio = Dio()
      ..httpClientAdapter =
          _FragmentedUnicodeResponse('event: delta\ndata: $event\n\n'
              'event: done\ndata: {}\n\n');
    final transport = AiAssistantTransport(
        dio: dio,
        baseUrl: 'https://unicode.test',
        tokenProvider: () => 'test-session',
        userProvider: () => 'self');
    final events = await AiAssistantStreamClient(transport)
        .open('/unicode', {'content': text}).toList();
    expect(events, hasLength(2));
    expect(events.first.kind, AiAssistantStreamKind.delta);
    expect(events.first.text.codeUnits, orderedEquals(' $text '.codeUnits));
    expect(events.last.kind, AiAssistantStreamKind.done);
    dio.close();
  });
}
