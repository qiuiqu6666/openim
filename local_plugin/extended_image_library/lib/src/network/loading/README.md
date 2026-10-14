# Display image loading

`ImageUtil.networkImage` opts in to `cancelWhenUnused`. Other provider consumers
retain their existing behavior unless explicitly opted in.

- `ImageLoadScheduler` bounds active download/first-frame-decode tasks to four. Decoded
  memory-cache hits do not enter the scheduler. Queued cancellation starts no I/O.
- `ImageLoadCacheContext` labels the synchronous pending-listener registration
  performed by `ImageCache.putIfAbsent`. No callback type, debug string, or guessed
  listener count is used to distinguish the cache from actual consumers.
- `ManagedImageStreamCompleter` starts when a widget or precache listener attaches.
  Consumers of the same decoded cache key share one task. The last consumer's
  removal cancels pending work after a microtask, allowing same-frame transfer.
  Cancellation is not a load error and cannot trigger the image's fallback URL.
- Different decode sizes have independent tasks, even for the same URL. Cancelling
  one never aborts another's request. A single global HTTP client is not closed.
- Waiting headers are aborted through their request. Waiting bodies are cancelled
  through their stream subscription: Dart's request abort alone cannot cancel a
  response after its headers have arrived. Partial response bytes never enter disk cache.
- Completed images retain Flutter's bounded decoded cache and existing disk cache.
  A kept-alive stream paused by TickerMode can restart after cancellation. The
  decoded delegate is released from `ImageStreamCompleter.onDisposed`, available
  in the application's pinned Flutter 3.41.6 SDK.

The scheduler and lifecycle implementation are isolated here; the existing
network provider owns URL identity, disk caching, deadlines and retry settings.
`test/utils/media/managed_network_image_test.dart` covers cancellation, sharing,
cache hits, response stalls and resume behavior using a real local HTTP server.
`prepared_image_codec_test.dart` verifies that native first-frame decoding holds
its slot, transfers its frame without a second decode, and releases a cancelled
frame/codec even if native decoding finishes after cancellation.
