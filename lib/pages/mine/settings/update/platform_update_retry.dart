/// Bounded automatic retries; an exhausted check remains eligible for retry.
Future<T> retryPlatformUpdate<T>(Future<T> Function() fetch,
    {Future<void> Function(Duration)? wait}) async {
  final delay = wait ?? Future<void>.delayed;
  for (var attempt = 0;; attempt++) {
    try {
      return await fetch();
    } catch (_) {
      if (attempt == 2) rethrow;
      await delay(Duration(seconds: attempt == 0 ? 1 : 3));
    }
  }
}
