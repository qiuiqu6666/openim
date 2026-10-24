import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      timeout: const Duration(minutes: 15),
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        final output = Platform.environment['RECALL_TEST_OUTPUT'];
        if (output == null) throw StateError('RECALL_TEST_OUTPUT is required');
        final result = {...?data};
        final screenshots = result.remove('screenshots') as List? ?? [];
        for (final screenshot in screenshots) {
          final name = screenshot['screenshotName'] as String;
          if (!RegExp(r'^[a-z_]+$').hasMatch(name)) {
            throw StateError('Invalid screenshot name');
          }
          await File('${File(output).parent.path}/$name.png')
              .writeAsBytes((screenshot['bytes'] as List).cast<int>());
        }
        await File(output)
            .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
        if (data?['completed'] != true ||
            (data?['results'] as List?)?.length != 2) {
          throw StateError('Incomplete real-device recall verification');
        }
      },
    );
