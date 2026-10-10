import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';

import '../../../support/unicode/unicode_samples.dart';

void main() {
  for (final sample in unicodeSamples) {
    test('profile draft keeps raw nickname and signature: ${sample.name}', () {
      final store = SettingsDraftStore();
      addTearDown(store.dispose);
      final raw = ' ${sample.text} ';
      store.seedProfile(nickname: raw, signature: raw);
      expect(store.profileNickname, raw);
      expect(store.profileSignature, raw);
    });
  }
}
