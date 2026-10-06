import '../../../../core/notifications/foreground_message_alert.dart';
import '../../../../core/notifications/message_notification_sound.dart';

/// Owned by the sound picker route; shares the notification audio adapter.
abstract class MessageNotificationSoundPreview {
  Future<void> stop();
  Future<void> load(String id);
  Future<void> play();
  Future<void> dispose();
}

class AudioMessageNotificationSoundPreview
    implements MessageNotificationSoundPreview {
  ForegroundMessageAlertPlayer? _player;
  bool _disposed = false;
  int _generation = 0;

  @override
  Future<void> stop() async {
    _generation++;
    await _player?.stop();
  }

  @override
  Future<void> load(String id) async {
    if (_disposed) return;
    final generation = _generation;
    final audio = _player ??= ForegroundMessageAlertPlayer.native();
    bool current() => !_disposed && generation == _generation;
    await audio.prepare();
    if (!current()) return;
    await audio.setAsset(MessageNotificationSoundIds.assetPath(id),
        package: 'openim_common');
    if (!current()) return;
    await audio.seekToStart();
  }

  @override
  Future<void> play() => _disposed
      ? Future<void>.value()
      : _player?.play() ?? Future<void>.value();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
