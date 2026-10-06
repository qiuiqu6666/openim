import 'dart:async';

/// Cancels route-owned previews when a call or account exit takes over audio.
/// The IM/app lifecycle keeps ownership; settings never register SDK listeners.
abstract final class NotificationSoundActivity {
  static final _interruptions = StreamController<void>.broadcast(sync: true);
  static Stream<void> get interruptions => _interruptions.stream;

  static void interruptPreviews() => _interruptions.add(null);
}
