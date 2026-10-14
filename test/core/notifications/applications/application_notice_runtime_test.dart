import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/applications/application_notice.dart';
import 'package:openim/core/notifications/applications/application_notice_runtime.dart';
import 'package:openim/core/notifications/message_notification_runtime.dart';

class Harness {
  MessageNotificationSession? owner = (accountID: 'me', sessionKey: 'session');
  bool ready = true, foreground = true, allowed = true, viewing = false;
  var time = DateTime.fromMillisecondsSinceEpoch(1000000);
  final seen = <String, List<String>>{};
  final shown = <String>[];
  final opened = <ApplicationNoticeKind>[];
  Future<ApplicationNotice?> Function(ApplicationNotice)? verify;
  late final runtime = ApplicationNoticeRuntime(
      session: () => owner,
      ready: () => ready,
      foreground: () => foreground,
      allowed: () => allowed,
      isViewing: (_) => viewing,
      now: () => time,
      verify: (event, _) async => verify == null ? event : verify!(event),
      show: (event, payload, current) async {
        if (current()) shown.add(payload);
      },
      open: opened.add,
      readSeen: (account) => seen[account] ?? [],
      writeSeen: (account, values) async {
        seen[account] = values;
      });
  ApplicationNotice event(
          {int at = 1000,
          String applicant = 'peer',
          String recipient = 'me',
          bool pending = true,
          ApplicationNoticeKind kind = ApplicationNoticeKind.friend}) =>
      ApplicationNotice(
          kind: kind,
          applicant: applicant,
          recipient: recipient,
          groupID: kind == ApplicationNoticeKind.group ? 'group' : '',
          createdAt: at,
          pending: pending);
}

void main() {
  test('live added event alerts once and persists account-specific identity',
      () async {
    final h = Harness();
    h.runtime.synchronize();
    await Future.wait(
        [h.runtime.receive(h.event()), h.runtime.receive(h.event())]);
    expect(h.shown.length, 1);
    expect(h.seen['me'], [h.event().eventKey]);
    final next = Harness();
    next.seen.addAll(h.seen);
    next.runtime.synchronize();
    await next.runtime.receive(next.event());
    expect(next.shown, isEmpty);
  });
  test('own, wrong-recipient, handled and historical requests never alert',
      () async {
    final h = Harness();
    h.runtime.synchronize();
    for (final event in [
      h.event(applicant: 'me'),
      h.event(recipient: 'other', applicant: 'a'),
      h.event(pending: false, applicant: 'b'),
      h.event(at: 999)
    ]) {
      await h.runtime.receive(event);
    }
    expect(h.shown, isEmpty);
  });
  test('background and sync callbacks cannot replay into foreground alerts',
      () async {
    for (final background in [true, false]) {
      final h = Harness();
      h.runtime.synchronize();
      if (background) {
        h.foreground = false;
      } else {
        h.ready = false;
      }
      h.runtime.synchronize();
      await h.runtime.receive(h.event());
      h.foreground = h.ready = true;
      h.runtime.synchronize();
      await h.runtime.receive(h.event());
      expect(h.shown, isEmpty);
    }
  });
  test('preferences and current application page suppress alerts', () async {
    for (final viewing in [true, false]) {
      final h = Harness()
        ..viewing = viewing
        ..allowed = viewing;
      h.runtime.synchronize();
      await h.runtime.receive(h.event());
      h.viewing = false;
      h.allowed = true;
      await h.runtime.receive(h.event());
      expect(h.shown, isEmpty);
    }
  });
  test(
      'authoritative rejection suppresses ordinary group member and processed request',
      () async {
    final h = Harness()..verify = (_) async => null;
    h.runtime.synchronize();
    await h.runtime.receive(h.event(kind: ApplicationNoticeKind.group));
    expect(h.shown, isEmpty);
  });
  test(
      'account switch during lookup cannot show or persist for the new account',
      () async {
    final reply = Completer<ApplicationNotice?>();
    final h = Harness()..verify = (_) => reply.future;
    h.runtime.synchronize();
    final work = h.runtime.receive(h.event());
    h.owner = (accountID: 'other', sessionKey: 'other-session');
    h.runtime.synchronize();
    reply.complete(h.event());
    await work;
    expect(h.shown, isEmpty);
    expect(h.seen, isEmpty);
  });
  test(
      'local click waits for SDK, opens once, and does not accept remote proposal or legacy text',
      () async {
    final h = Harness();
    h.runtime.synchronize();
    await h.runtime.receive(h.event());
    final payload = h.shown.single;
    h.ready = false;
    expect(h.runtime.handleTap(payload), isTrue);
    expect(h.opened, isEmpty);
    h.ready = true;
    h.runtime.synchronize();
    h.runtime.handleTap(payload);
    expect(h.opened, [ApplicationNoticeKind.friend]);
    expect(h.runtime.handleTap('新的好友申请'), isFalse);
    expect(
        h.runtime.handleTap(
            jsonEncode({'version': 1, 'type': 'friend_application'})),
        isFalse);
  });
  test('local click for another account or version never navigates', () async {
    final h = Harness();
    h.runtime.synchronize();
    await h.runtime.receive(h.event());
    final value = jsonDecode(h.shown.single) as Map<String, dynamic>;
    h.runtime.handleTap(jsonEncode({...value, 'accountID': 'other'}));
    h.runtime.handleTap(jsonEncode({...value, 'version': 2}));
    expect(h.opened, isEmpty);
  });
  test('close fences a pending lookup', () async {
    final reply = Completer<ApplicationNotice?>();
    final h = Harness()..verify = (_) => reply.future;
    h.runtime.synchronize();
    final pending = h.runtime.receive(h.event());
    h.runtime.close();
    reply.complete(h.event());
    await pending;
    expect(h.shown, isEmpty);
  });
}
