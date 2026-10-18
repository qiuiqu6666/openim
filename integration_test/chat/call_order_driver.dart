import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Platform.environment['CALL_ORDER_OUTPUT'];
  if (output == null) throw StateError('CALL_ORDER_OUTPUT is required');
  await Directory(output).create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, image, [args]) async {
      await File('$output/$name.png').writeAsBytes(image);
      return image.isNotEmpty;
    },
    responseDataCallback: (data) async {
      final result = {...?data}..remove('screenshots');
      await File('$output/result.json').writeAsString(jsonEncode(result));
    },
  );
}
