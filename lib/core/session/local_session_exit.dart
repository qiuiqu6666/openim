import 'dart:async';

/// Native cleanup keeps its place in the SDK session queue, but does not hold
/// the local sign-out screen open. Timing out cleanup would not cancel it.
Future<void> exitLocalSession({
  required Future<void> Function() logoutSdk,
  required Future<void> Function() clearLocal,
  required void Function() navigate,
  required void Function(Object, StackTrace) onCleanupError,
}) async {
  final cleanup = Future<void>.sync(logoutSdk);
  unawaited(cleanup.catchError(onCleanupError));
  try {
    await clearLocal();
  } finally {
    navigate();
  }
}
