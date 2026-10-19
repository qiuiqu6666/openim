import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/data/live_avatar_cache.dart';

void main() {
  test(
      'avatars survive host recreation but stay isolated by runtime and anchor',
      () {
    final runtime = Object();
    LiveAvatarCache.write(
        runtime, 'self|group|anchor', 'https://example.com/a.png');
    expect(LiveAvatarCache.read(runtime, 'self|group|anchor'),
        'https://example.com/a.png');
    expect(LiveAvatarCache.read(Object(), 'self|group|anchor'), isEmpty);
    expect(LiveAvatarCache.read(runtime, 'self|group|other'), isEmpty);
    LiveAvatarCache.write(runtime, 'self|group|anchor', '');
    expect(LiveAvatarCache.read(runtime, 'self|group|anchor'), isEmpty);
  });
}
