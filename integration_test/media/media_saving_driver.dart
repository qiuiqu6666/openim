import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        final output = Platform.environment['MEDIA_DEVICE_OUTPUT'];
        if (output == null) throw StateError('MEDIA_DEVICE_OUTPUT required');
        await File(output)
            .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
        if (data?['completed'] != true ||
            (data?['results'] as Map?)?['video'] == null) {
          throw StateError('Incomplete media device regression');
        }
      },
    );
