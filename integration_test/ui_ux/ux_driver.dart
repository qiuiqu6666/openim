import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Platform.environment['UX_AUDIT_OUTPUT'];
  if (output == null) throw StateError('UX_AUDIT_OUTPUT is required');
  final serial = Platform.environment['UX_DEVICE_SERIAL'];
  if (serial == null) throw StateError('UX_DEVICE_SERIAL is required');
  await Directory(output).create(recursive: true);
  final keyboardSetting = await Process.run('adb', [
    '-s',
    serial,
    'shell',
    'settings',
    'get',
    'secure',
    'show_ime_with_hard_keyboard'
  ]);
  if (keyboardSetting.exitCode != 0) {
    throw StateError('Cannot read IME setting');
  }
  final originalKeyboard = '${keyboardSetting.stdout}'.trim();
  final enableKeyboard = await Process.run('adb', [
    '-s',
    serial,
    'shell',
    'settings',
    'put',
    'secure',
    'show_ime_with_hard_keyboard',
    '1'
  ]);
  if (enableKeyboard.exitCode != 0) throw StateError('Cannot show system IME');
  // Android screenshot callbacks arrive after the suite. Input uses an explicit
  // live marker, and only the fixed test text is ever typed.
  final inputLog = await Process.start('adb',
      ['-s', serial, 'logcat', '-v', 'brief', '-T', '1', 'flutter:I', '*:S']);
  final typedThemes = <String>{};
  final pendingInputs = <Future<void>>[];
  final logSubscription = inputLog.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    for (final theme in ['light', 'dark']) {
      if (!line.contains('UX_AUDIT_INPUT_READY:$theme') ||
          !typedThemes.add(theme)) {
        continue;
      }
      pendingInputs.add(() async {
        final typed = await Process.run(
            'adb', ['-s', serial, 'shell', 'input', 'text', 'UX%sdraft%skeep']);
        if (typed.exitCode != 0) {
          throw StateError('Android input failed: ${typed.stderr}');
        }
      }());
    }
  });
  try {
    await integrationDriver(
      writeResponseOnFailure: true,
      onScreenshot: (name, image, [args]) async {
        await File('$output/$name.png').writeAsBytes(image);
        return image.isNotEmpty;
      },
      responseDataCallback: (data) async {
        final summary = {...?data}..remove('screenshots');
        await File('$output/device-results.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
        if (data?['completed'] != true) {
          throw StateError(
              'Device run incomplete; do not accept partial results');
        }
      },
    );
  } finally {
    await logSubscription.cancel();
    inputLog.kill();
    await Process.run('adb', [
      '-s',
      serial,
      'shell',
      'settings',
      originalKeyboard == 'null' ? 'delete' : 'put',
      'secure',
      'show_ime_with_hard_keyboard',
      if (originalKeyboard != 'null') originalKeyboard,
    ]);
    await Future.wait(pendingInputs);
  }
}
