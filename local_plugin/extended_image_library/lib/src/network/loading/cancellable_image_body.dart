import 'dart:async';

import 'image_load_scheduler.dart';

/// HttpClientRequest.abort only aborts before headers. Cancel the subscription
/// as well so a response body which has stopped sending is released promptly.
Stream<List<int>> cancellableImageBody(
  Stream<List<int>> body,
  ImageLoadSignal? signal,
) async* {
  if (signal == null) {
    yield* body;
    return;
  }
  final iterator = StreamIterator(body);
  final unregister = signal.onCancel(() => unawaited(iterator.cancel()));
  try {
    while (await signal.bind(iterator.moveNext())) {
      signal.check();
      yield iterator.current;
    }
    signal.check();
  } finally {
    unregister();
    await iterator.cancel();
  }
}
