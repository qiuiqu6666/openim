import 'dart:async';

/// Two preparation workers share a bounded queue; delivery stays in input order.
/// Failed preparation never blocks later items or triggers an automatic resend.
Future<void> runOrderedMediaBatch<T>(
  List<T> items, {
  required Future<void> Function(T) prepare,
  required Future<void> Function(T) send,
  required void Function(T, Object) onError,
  required bool Function() isClosed,
  int concurrency = 2,
}) async {
  if (concurrency < 1) throw ArgumentError.value(concurrency);
  final ready = List.generate(items.length, (_) => Completer<bool>());
  var cursor = 0;
  Future<void> worker() async {
    while (cursor < items.length) {
      final index = cursor++;
      if (isClosed()) {
        ready[index].complete(false);
        continue;
      }
      try {
        await prepare(items[index]);
        ready[index].complete(!isClosed());
      } catch (error) {
        if (!isClosed()) onError(items[index], error);
        ready[index].complete(false);
      }
    }
  }

  final workers = List.generate(concurrency, (_) => worker());
  for (var index = 0; index < items.length; index++) {
    if (await ready[index].future && !isClosed()) {
      try {
        await send(items[index]);
      } catch (error) {
        if (!isClosed()) onError(items[index], error);
      }
    }
  }
  await Future.wait(workers);
}
