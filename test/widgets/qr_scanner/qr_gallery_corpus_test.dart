import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/qr_gallery/run_corpus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native ZXing corpus: content, positions, formats and bounded failure',
      () async {
    final rows = await runQrCorpus();
    for (final row in rows) {
      debugPrint(jsonEncode(row));
    }
    expect(rows.where((row) => row['passed'] != true).toList(), isEmpty);
  },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: !const bool.fromEnvironment('QR_NATIVE_TESTS'));
}
