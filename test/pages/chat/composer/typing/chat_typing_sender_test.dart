import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/core/privacy/typing_visibility_preferences.dart';
import 'package:openim/pages/chat/composer/typing/chat_typing_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatTypingSender sender;
  late List<bool> sent;
  var current = true;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    sent = [];
    current = true;
    sender = ChatTypingSender(
        owner: 'alice',
        isCurrent: () => current,
        send: (value) async {
          sent.add(value);
        });
  });
  tearDown(() => sender.dispose());

  test('default is enabled and preferences survive reload per account',
      () async {
    expect(TypingVisibilityPreferences.read('alice'), isTrue);
    await TypingVisibilityPreferences.write('alice', false);
    await SpUtil().init();
    expect(TypingVisibilityPreferences.read('alice'), isFalse);
    expect(TypingVisibilityPreferences.read('bob'), isTrue);
  });
  test('enabled sends start and stop', () async {
    sender.report(true);
    sender.report(false);
    await sender.settled;
    expect(sent, [true, false]);
  });
  test('disabled suppresses start and idle events; enabling takes effect',
      () async {
    await TypingVisibilityPreferences.write('alice', false);
    sender.report(true);
    sender.report(false);
    await sender.settled;
    expect(sent, isEmpty);
    await TypingVisibilityPreferences.write('alice', true);
    sender.report(true);
    await sender.settled;
    expect(sent, [true]);
  });
  test('disable clears an announced status once', () async {
    sender.report(true);
    await sender.settled;
    await TypingVisibilityPreferences.write('alice', false);
    sender.report(false);
    sender.report(true);
    await sender.settled;
    expect(sent, [true, false]);
  });
  test('disable drops queued starts and clears after in-flight start',
      () async {
    sender.dispose();
    final gate = Completer<void>();
    sender = ChatTypingSender(
        owner: 'alice',
        isCurrent: () => current,
        send: (value) async {
          sent.add(value);
          if (value) await gate.future;
        });
    sender.report(true);
    await Future<void>.delayed(Duration.zero);
    sender.report(true);
    await TypingVisibilityPreferences.write('alice', false);
    gate.complete();
    await sender.settled;
    expect(sent, [true, false]);
  });
  test('other account changes do not clear this conversation', () async {
    sender.report(true);
    await sender.settled;
    await TypingVisibilityPreferences.write('bob', false);
    await sender.settled;
    expect(sent, [true]);
  });
  test('old session and disposed sender cannot publish queued input', () async {
    sender.report(true);
    current = false;
    await sender.settled;
    expect(sent, isEmpty);
    current = true;
    sender.report(true);
    sender.dispose();
    await sender.settled;
    expect(sent, isEmpty);
  });
}
