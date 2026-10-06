import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:openim/pages/ai_assistant/controller/ai_assistant_controller.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_api.dart';
import 'package:openim/pages/ai_assistant/data/ai_assistant_sse.dart';

class AiControllerTestHarness {
  AiControllerTestHarness({bool? serviceEnabled}) {
    controller = AiAssistantController(
      api: api,
      serviceEnabled: serviceEnabled,
      sessionProvider: () => session,
    );
  }

  AiAssistantSession session = (userID: 'owner', token: 'owner-token');
  final api = AiControllerTestApi();
  late final AiAssistantController controller;

  void changeSession({bool sameAccount = false}) {
    session = (
      userID: sameAccount ? session.userID : 'next-owner',
      token: 'next-token',
    );
    controller.checkSession();
  }

  void dispose() {
    controller.dispose();
    api.dispose();
  }
}

class AiControllerTestApi extends AiAssistantApi {
  AiControllerTestApi()
      : super(
          dio: Dio(),
          baseUrl: 'https://ai.invalid',
          userProvider: () => 'owner',
          tokenProvider: () => 'owner-token',
        );

  Future<AiAssistantHistoryPage> Function()? onHistory;
  final historyTokens = <CancelToken?>[];
  final turns = <AiControllerTestTurn>[];
  int uploadCalls = 0;
  int deleteCalls = 0;
  int downloadCalls = 0;

  @override
  Future<AiAssistantHistoryPage> history({
    int limit = 50,
    String? cursor,
    CancelToken? cancelToken,
  }) {
    historyTokens.add(cancelToken);
    return onHistory?.call() ??
        Future.value(const AiAssistantHistoryPage(items: [], hasMore: false));
  }

  @override
  Stream<AiAssistantStreamEvent> streamChat({
    String? capability,
    required String content,
    AiAssistantAnalyze? analyze,
    List<String>? fileIds,
    CancelToken? cancelToken,
  }) {
    final turn = AiControllerTestTurn(content, cancelToken);
    turns.add(turn);
    return turn.events.stream;
  }

  @override
  Future<AiAssistantUploadedFile> uploadFile({
    required String fileName,
    String? path,
    Uint8List? bytes,
    String? mimeType,
    CancelToken? cancelToken,
  }) async {
    uploadCalls++;
    return AiAssistantUploadedFile(
      fileId: 'uploaded-file',
      fileName: fileName,
      contentType: mimeType ?? 'image/png',
      sizeBytes: bytes?.length ?? 1,
    );
  }

  @override
  Future<int> deleteHistory({CancelToken? cancelToken}) async {
    deleteCalls++;
    return 0;
  }

  @override
  Future<Uint8List> downloadFile(String fileId,
      {CancelToken? cancelToken}) async {
    downloadCalls++;
    throw StateError('Controller must not download files');
  }

  void dispose() {
    for (final turn in turns) {
      unawaited(turn.events.close());
    }
  }
}

/// Ignores cancellation on purpose so controller ownership guards are exercised.
class AiControllerTestTurn {
  AiControllerTestTurn(this.content, this.token);

  final String content;
  final CancelToken? token;
  final events = StreamController<AiAssistantStreamEvent>.broadcast(sync: true);
  final parser = AiAssistantSseParser();

  void fragment(String source) {
    parser.feed(source, (name, data) {
      final event = AiAssistantStreamEvent.parse(name, data);
      if (event != null) events.add(event);
    });
  }

  void delta(String text) =>
      fragment('event: delta\ndata: ${jsonEncode({'text': text})}\n\n');

  void done() => fragment('event: done\ndata: {}\n\n');
}

AiAssistantHistoryPage aiControllerHistory(String id, String text) =>
    AiAssistantHistoryPage(
      items: [
        AiAssistantHistoryItem.fromJson({
          'id': id,
          'role': 'assistant',
          'content': text,
          'capability': 'chat',
          'status': 'complete',
          'createdAt': 1720000000000,
        }),
      ],
      hasMore: false,
    );
