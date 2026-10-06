import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// One streaming hash worker at a time. Only a file path and message ports cross
/// the isolate boundary; media bytes never accumulate on the UI isolate.
class DeviceSyncHasher {
  bool _busy = false;
  bool _disposed = false;
  CancelToken? _activeToken;

  Future<String> hash(File file, {required CancelToken cancelToken}) async {
    if (_disposed) throw StateError('Device sync hasher is disposed');
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;
    if (_busy) throw StateError('A device sync hash is already running');
    _busy = true;
    _activeToken = cancelToken;

    final replies = ReceivePort();
    final failures = ReceivePort();
    final exits = ReceivePort();
    final outcome = Completer<String>();
    // Install an error listener before spawn completes: cancellation may arrive
    // while the VM is still creating the isolate.
    unawaited(outcome.future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    final exited = Completer<void>();
    Isolate? worker;
    SendPort? control;
    Timer? cancelDeadline;
    var cancelled = false;
    var finished = false;

    void cancelWorker(DioException error) {
      if (finished || cancelled) return;
      cancelled = true;
      control?.send('cancel');
      // Allow the worker to cancel its file subscription and close its digest
      // sink. If it cannot answer, terminate it; this also releases its handles.
      cancelDeadline = Timer(const Duration(milliseconds: 250), () {
        worker?.kill(priority: Isolate.immediate);
        if (!outcome.isCompleted) outcome.completeError(error);
      });
    }

    final repliesSubscription = replies.listen((message) {
      if (message is SendPort) {
        control = message;
        if (cancelled) control!.send('cancel');
      } else if (message is List && message.length == 2) {
        if (outcome.isCompleted) return;
        if (cancelled || message[0] == 'cancelled') {
          outcome.completeError(cancelToken.cancelError ??
              DioException.requestCancelled(
                  requestOptions: RequestOptions(), reason: 'Hash cancelled'));
        } else if (message[0] == 'digest') {
          outcome.complete(message[1] as String);
        } else {
          outcome.completeError(FileSystemException(message[1] as String));
        }
      }
    });
    final failuresSubscription = failures.listen((message) {
      if (outcome.isCompleted) return;
      outcome.completeError(cancelled
          ? cancelToken.cancelError!
          : StateError('Device sync hash worker failed: $message'));
    });
    final exitsSubscription = exits.listen((_) {
      if (!exited.isCompleted) exited.complete();
      // An exit message and the last result use distinct ports. Give the result
      // port one event-loop turn before reporting an unexpected worker exit.
      Timer.run(() {
        if (!outcome.isCompleted) {
          outcome.completeError(cancelled
              ? cancelToken.cancelError!
              : StateError('Device sync hash worker exited without a result'));
        }
      });
    });
    unawaited(cancelToken.whenCancel.then(cancelWorker));

    try {
      worker = await Isolate.spawn(
        _hashOriginalFile,
        (file.path, replies.sendPort),
        onError: failures.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
        debugName: 'device-sync-sha256',
      );
      if (cancelToken.isCancelled) cancelWorker(cancelToken.cancelError!);
      return await outcome.future;
    } finally {
      finished = true;
      cancelDeadline?.cancel();
      worker?.kill(priority: Isolate.immediate);
      if (worker != null && !exited.isCompleted) {
        await exited.future
            .timeout(const Duration(seconds: 1), onTimeout: () {});
      }
      await repliesSubscription.cancel();
      await failuresSubscription.cancel();
      await exitsSubscription.cancel();
      replies.close();
      failures.close();
      exits.close();
      _activeToken = null;
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    final token = _activeToken;
    if (token != null && !token.isCancelled) {
      token.cancel('Device sync hasher disposed');
    }
  }
}

Future<void> _hashOriginalFile((String, SendPort) request) async {
  final (path, reply) = request;
  final commands = ReceivePort();
  final done = Completer<void>();
  final digestSink = _DeviceSyncDigestSink();
  final input = sha256.startChunkedConversion(digestSink);
  StreamSubscription<List<int>>? reading;
  var cancelled = false;
  var responded = false;
  var inputClosed = false;

  void closeInput() {
    if (inputClosed) return;
    inputClosed = true;
    input.close();
  }

  void respond(String status, String value) {
    if (responded) return;
    responded = true;
    reply.send([status, value]);
    if (!done.isCompleted) done.complete();
  }

  final commandSubscription = commands.listen((message) async {
    if (message != 'cancel' || responded) return;
    cancelled = true;
    await reading?.cancel();
    closeInput();
    respond('cancelled', '');
  });
  reply.send(commands.sendPort);

  try {
    final original = File(path);
    final before = await original.stat();
    if (cancelled) return;
    reading = original.openRead().listen(
          input.add,
          onError: (Object error) => respond('error', error.toString()),
          onDone: () async {
            if (cancelled) return;
            closeInput();
            final after = await original.stat();
            if (cancelled) return;
            if (before.size != after.size ||
                before.modified != after.modified) {
              respond('error', 'Original file changed while hashing');
            } else {
              respond('digest', digestSink.digest!.toString());
            }
          },
          cancelOnError: true,
        );
    await done.future;
  } catch (error) {
    respond('error', error.toString());
  } finally {
    await reading?.cancel();
    await commandSubscription.cancel();
    commands.close();
  }
}

class _DeviceSyncDigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
