/// Bounded independent image/video lanes; each item sends as soon as ready.
/// Failed preparation never sends that item or triggers an automatic resend.
Future<void> runReadyMediaBatch<T>(
  List<T> items, {
  required Future<void> Function(T) prepare,
  required Future<void> Function(T) send,
  required void Function(T, Object) onError,
  required bool Function() isClosed,
  bool Function(T)? isVideo,
  Future<void> Function(T)? waitUntilReady,
  int concurrency = 4,
}) async {
  if (concurrency < 1) throw ArgumentError.value(concurrency);
  final confirmations = <Future<void>>[];
  Future<void> confirm(T item) async {
    try {
      if (!isClosed()) await send(item);
    } catch (error) {
      if (!isClosed()) onError(item, error);
    }
  }

  Future<void> lane(List<T> queue, int workers) async {
    var cursor = 0;
    // Resolve local preparation outside upload slots. A slow photo-library
    // read or encoder must not hide already prepared items behind its index.
    final pending = waitUntilReady == null
        ? null
        : {
            for (var i = 0; i < queue.length; i++)
              i: waitUntilReady(queue[i])
                  .then((_) => i, onError: (Object _) => i),
          };
    Future<void> worker() async {
      while (!isClosed()) {
        late final T item;
        if (pending == null) {
          if (cursor >= queue.length) return;
          item = queue[cursor++];
        } else {
          if (pending.isEmpty) return;
          final index = await Future.any(pending.values);
          if (pending.remove(index) == null) continue;
          if (isClosed()) return;
          item = queue[index];
        }
        try {
          await prepare(item);
          // A receipt owns no upload resources. Observe it immediately without
          // holding this worker; keep the batch alive until all receipts settle.
          if (!isClosed()) confirmations.add(confirm(item));
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
  await Future.wait(confirmations);
}
