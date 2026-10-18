/// Bounded independent image/video lanes; each item sends as soon as ready.
/// Failed preparation never sends that item or triggers an automatic resend.
Future<void> runReadyMediaBatch<T>(
  List<T> items, {
  required Future<void> Function(T) prepare,
  required Future<void> Function(T) send,
  required void Function(T, Object) onError,
  required bool Function() isClosed,
  bool Function(T)? isVideo,
  int concurrency = 2,
}) async {
  if (concurrency < 1) throw ArgumentError.value(concurrency);
  Future<void> lane(List<T> queue, int workers) async {
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < queue.length && !isClosed()) {
        final item = queue[cursor++];
        try {
          await prepare(item);
          if (!isClosed()) await send(item);
        } catch (error) {
          if (!isClosed()) onError(item, error);
        }
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
  }

  await Future.wait([
    lane(items.where((item) => !(isVideo?.call(item) ?? false)).toList(),
        concurrency),
    lane(items.where((item) => isVideo?.call(item) ?? false).toList(), 1),
  ]);
}
