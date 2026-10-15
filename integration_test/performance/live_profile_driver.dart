import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final output = Platform.environment['CHAT_PROFILE_OUTPUT'];
      if (output == null) throw StateError('CHAT_PROFILE_OUTPUT is required');
      await File(output).writeAsString(jsonEncode(data));
      if (data?['runCompleted'] != true ||
          (data?['results'] as List?)?.length != 9) {
        throw StateError(
            'Incomplete live profile; reject partial measurements');
      }
    });
