import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/device_sync/models/device_sync_preferences.dart';

void main() {
  test('the signed-out state has no enabled sync', () {
    const preferences = DeviceSyncPreferences();
    expect(preferences.accountID, isEmpty);
    expect(preferences.enabled, isFalse);
  });

  test('an account without saved preferences defaults to all four switches on',
      () {
    final preferences = DeviceSyncPreferences.fromJson('owner', null);
    expect(preferences.accountID, 'owner');
    expect(preferences.enabled, isTrue);
    expect(preferences.photos, isTrue);
    expect(preferences.location, isTrue);
    expect(preferences.videos, isTrue);
    expect(preferences.wifiOnly, isTrue);
  });

  test('unconfirmed legacy preferences migrate to the login defaults', () {
    for (final value in [
      <String, dynamic>{},
      {
        'version': 1,
        'consentDecided': false,
        'photos': false,
        'videos': true,
        'location': false,
        'wifiOnly': false,
      },
      {
        'photos': false,
        'videos': true,
        'location': false,
        'wifiOnly': false,
      },
    ]) {
      final preferences = DeviceSyncPreferences.fromJson('owner', value);
      expect(preferences.accountID, 'owner');
      expect(preferences.photos, isTrue);
      expect(preferences.location, isTrue);
      expect(preferences.videos, isTrue);
      expect(preferences.wifiOnly, isTrue);
    }
  });

  test('missing saved switches use defaults without overwriting explicit off',
      () {
    for (final disabled in ['photos', 'videos', 'location', 'wifiOnly']) {
      final preferences = DeviceSyncPreferences.fromJson('owner', {
        'version': 1,
        'consentDecided': true,
        disabled: false,
      });
      final restored =
          DeviceSyncPreferences.fromJson('owner', preferences.toJson());
      final values = restored.toJson();
      for (final key in ['photos', 'videos', 'location', 'wifiOnly']) {
        expect(values[key], key != disabled);
      }
    }
  });

  test('a previously confirmed opt-out stays disabled after migration', () {
    final preferences = DeviceSyncPreferences.fromJson('owner', {
      'version': 1,
      'consentDecided': true,
      'photos': false,
      'videos': false,
      'location': false,
      'wifiOnly': false,
    });
    expect(preferences.enabled, isFalse);
    expect(preferences.photos, isFalse);
    expect(preferences.location, isFalse);
    expect(preferences.videos, isFalse);
    expect(preferences.wifiOnly, isFalse);
  });

  test('confirmed legacy choices preserve each switch independently', () {
    for (final photos in [false, true]) {
      for (final location in [false, true]) {
        for (final videos in [false, true]) {
          for (final wifiOnly in [false, true]) {
            final preferences = DeviceSyncPreferences.fromJson('owner', {
              'version': 1,
              'consentDecided': true,
              'photos': photos,
              'videos': videos,
              'location': location,
              'wifiOnly': wifiOnly,
            });
            expect(preferences.photos, photos);
            expect(preferences.location, location);
            expect(preferences.videos, videos);
            expect(preferences.wifiOnly, wifiOnly);
            expect(preferences.enabled, photos || location);
          }
        }
      }
    }
  });

  test('saved choices round-trip without restoring the login defaults', () {
    final defaults = DeviceSyncPreferences.fromJson('owner', null);
    for (final preferences in [
      defaults,
      defaults.copyWith(photos: false, videos: true, wifiOnly: false),
      defaults.copyWith(location: false),
      defaults.copyWith(
          photos: false, videos: false, location: false, wifiOnly: false),
    ]) {
      final json = preferences.toJson();
      final restored = DeviceSyncPreferences.fromJson('owner', json);
      expect(restored.accountID, 'owner');
      expect(restored.photos, preferences.photos);
      expect(restored.location, preferences.location);
      expect(restored.videos, preferences.videos);
      expect(restored.wifiOnly, preferences.wifiOnly);
      expect(restored.enabled, preferences.enabled);
      expect(json['version'], 1);
      expect(json['consentDecided'], isTrue);
    }
  });
}
