import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'ai_assistant_contract.dart';
import 'ai_assistant_exception.dart';
import 'ai_assistant_sse.dart';
import 'ai_assistant_transport.dart';

class AiAssistantStreamClient {
  AiAssistantStreamClient(this.transport);
  final AiAssistantTransport transport;

  Stream<AiAssistantStreamEvent> open(String path, Map<String, dynamic> body,
      {CancelToken? cancelToken}) {
    final internal = CancelToken();
    final finished = Completer<void>();
    late StreamController<AiAssistantStreamEvent> output;
    var stopped = false;
    Future<void> run() async {
      try {
        final owner = transport.session();
        final response = await transport.request<ResponseBody>(path,
            method: 'POST',
            body: body,
            responseType: ResponseType.stream,
            cancelToken: internal,
            captured: owner);
        final payload = response.data;
        final type = response.headers.value(Headers.contentTypeHeader) ?? '';
        if (payload == null) {
          throw const AiAssistantException('INVALID_RESPONSE', '助手未返回响应');
        }
        if (response.statusCode != 200 ||
            !type.toLowerCase().contains('text/event-stream')) {
          // Bound gateway bodies; the transport keeps raw HTML out of the UI.
          var errorBody = '';
          await for (final chunk
              in payload.stream.cast<List<int>>().transform(utf8.decoder)) {
            errorBody += chunk;
            if (errorBody.length > 65536) break;
          }
          throw transport.failure(errorBody, response.statusCode ?? 0);
        }
        final parser = AiAssistantSseParser();
        var terminal = false;
        await for (final chunk
            in payload.stream.cast<List<int>>().transform(utf8.decoder)) {
          if (stopped) break;
          transport.check(owner);
          parser.feed(chunk, (event, data) {
            if (terminal || stopped) return;
            final parsed = AiAssistantStreamEvent.parse(event, data);
            if (parsed == null) return;
            terminal = parsed.kind == AiAssistantStreamKind.done ||
                parsed.kind == AiAssistantStreamKind.error;
            output.add(parsed);
          });
          if (terminal) break;
        }
        if (!stopped) {
          if (terminal) {
            parser.reset();
          } else {
            parser.finish();
            throw const AiAssistantException(
                'INCOMPLETE_STREAM', '回复中断，请查看历史记录后重试');
          }
        }
      } catch (error, stack) {
        if (!stopped && !output.isClosed) {
          final mapped = error is AiAssistantException
              ? error
              : error is DioException && CancelToken.isCancel(error)
                  ? const AiAssistantException('CANCELLED', '')
                  : const AiAssistantException(
                      'INCOMPLETE_STREAM', '回复中断，请查看历史记录后重试');
          output.addError(mapped, stack);
        }
      } finally {
        if (!internal.isCancelled) internal.cancel('Assistant stream finished');
        if (!output.isClosed) unawaited(output.close());
        if (!finished.isCompleted) finished.complete();
      }
    }

    output = StreamController<AiAssistantStreamEvent>(
        onListen: () => unawaited(run()),
        onCancel: () {
          stopped = true;
          if (!internal.isCancelled) internal.cancel('Assistant stream closed');
          // Keep the response listener until Dio delivers its cancellation.
          // Awaiting this boundary also waits for await-for to release it.
          return finished.future;
        });
    if (cancelToken?.isCancelled == true) {
      internal.cancel('Assistant request cancelled');
    }
    cancelToken?.whenCancel.then((_) {
      if (!internal.isCancelled) internal.cancel('Assistant request cancelled');
    });
    return output.stream;
  }
}
