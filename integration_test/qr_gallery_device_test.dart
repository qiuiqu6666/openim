import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/support/qr_gallery/run_corpus.dart';
import '../test/support/qr_gallery/run_task_probe.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('album recognition native device corpus', (tester) async {
    final rows = await runQrCorpus(includeHeic: true);
    final tasks = await runQrTaskProbe();
    binding.reportData = {'qrGallery': rows, 'tasks': tasks};
    for (final row in rows) {
      debugPrint(jsonEncode(row));
    }
    debugPrint(jsonEncode({'tasks': tasks}));
    expect(rows.where((row) => row['passed'] != true).toList(), isEmpty);
    expect(tasks['passed'], isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
