import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/openim_profile_service.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';

void main() {
  test('signature updates preserve unrelated SDK extension fields', () {
    final ex = OpenIMProfileService.signatureEx(
        '{"other":{"enabled":true},"signature":"old"}', 'new');
    expect(jsonDecode(ex), {
      'other': {'enabled': true},
      'signature': 'new',
    });
    expect(OpenIMProfileService.signatureFromEx(ex), 'new');
    expect(
        OpenIMProfileService.signatureFromEx(
            OpenIMProfileService.signatureEx(ex, '')),
        '');
  });
  test('unknown extension formats cannot be overwritten', () {
    for (final ex in ['opaque-data', '[]', 'null']) {
      expect(
          () => OpenIMProfileService.signatureEx(ex, 'new'), throwsA(anything));
      expect(OpenIMProfileService.signatureFromEx(ex), '');
    }
    expect(OpenIMProfileService.signatureFromEx(null), '');
    expect(jsonDecode(OpenIMProfileService.signatureEx(null, 'bio')),
        {'signature': 'bio'});
  });
  test('default settings remain unavailable', () {
    const service = StubSettingsService();
    expect(service.isBackendAvailable, isFalse);
    expect(service.isProfileBackendAvailable, isFalse);
  });
}
