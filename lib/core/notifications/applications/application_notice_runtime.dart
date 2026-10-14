import 'dart:convert';
import '../message_notification_runtime.dart' show MessageNotificationSession;
import 'application_notice.dart';

/// Only live, foreground Added callbacks may alert. Snapshots never alert.
class ApplicationNoticeRuntime {
  ApplicationNoticeRuntime(
      {required this.session,
      required this.ready,
      required this.foreground,
      required this.allowed,
      required this.isViewing,
      required this.verify,
      required this.show,
      required this.open,
      required this.readSeen,
      required this.writeSeen,
      DateTime Function()? now})
      : now = now ?? DateTime.now;
  final MessageNotificationSession? Function() session;
  final bool Function() ready, foreground, allowed;
  final bool Function(ApplicationNoticeKind) isViewing;
  final Future<ApplicationNotice?> Function(ApplicationNotice, String) verify;
  final Future<void> Function(ApplicationNotice, String, bool Function()) show;
  final void Function(ApplicationNoticeKind) open;
  final List<String> Function(String) readSeen;
  final Future<void> Function(String, List<String>) writeSeen;
  final DateTime Function() now;
  MessageNotificationSession? _armed;
  int? _since;
  int _epoch = 0;
  bool _closed = false;
  final _inFlight = <String>{};
  final _observed = <String>{};
  final _openedTaps = <String>{};
  ({String account, String sessionKey, ApplicationNoticeKind kind})? _tap;

  void synchronize() {
    if (_closed) return;
    final current = session();
    if (!ready() || !foreground() || current == null) {
      _armed = null;
      _since = null;
      _epoch++;
      return;
    }
    if (_armed != current) {
      _armed = current;
      _since = now().millisecondsSinceEpoch ~/ 1000;
      _epoch++;
    }
    final tap = _tap;
    _tap = null;
    if (tap != null &&
        tap.account == current.accountID &&
        tap.sessionKey == current.sessionKey) {
      open(tap.kind);
    }
  }

  Future<void> receive(ApplicationNotice event) async {
    final owner = session();
    final seconds = now().millisecondsSinceEpoch ~/ 1000;
    if (_closed || owner == null) return;
    final key = '${owner.accountID}:${event.eventKey}';
    // Suppressed callbacks must not turn into alerts after resume/page changes.
    if (!_observed.add(key)) return;
    if (_observed.length > 1024) _observed.remove(_observed.first);
    if (_closed ||
        _armed != owner ||
        _since == null ||
        !ready() ||
        !foreground() ||
        !event.pending ||
        event.applicant.isEmpty ||
        event.applicant == owner.accountID ||
        event.seconds < _since! ||
        event.seconds > seconds + 5 ||
        seconds - event.seconds > 60 ||
        (event.kind == ApplicationNoticeKind.friend &&
            event.recipient != owner.accountID) ||
        (event.kind == ApplicationNoticeKind.group && event.groupID.isEmpty)) {
      return;
    }
    if (readSeen(owner.accountID).contains(event.eventKey) ||
        !_inFlight.add(key)) {
      return;
    }
    final epoch = _epoch;
    bool current() =>
        !_closed &&
        _epoch == epoch &&
        session() == owner &&
        ready() &&
        foreground() &&
        allowed() &&
        !isViewing(event.kind);
    try {
      final verified = await verify(event, owner.accountID);
      if (verified == null ||
          !verified.pending ||
          verified.eventKey != event.eventKey ||
          !current()) {
        return;
      }
      final seen = readSeen(owner.accountID).toSet()..add(event.eventKey);
      final recent = seen.toList();
      await writeSeen(owner.accountID,
          recent.length > 512 ? recent.sublist(recent.length - 512) : recent);
      if (!current()) return;
      final payload = jsonEncode({
        'version': 1,
        'type': 'local_application',
        'accountID': owner.accountID,
        'sessionKey': owner.sessionKey,
        'kind': event.kind.name,
        'eventID': event.eventKey
      });
      await show(verified, payload, current);
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Client-generated local payload only; never parse titles or legacy APNs ex.
  bool handleTap(String? payload) {
    try {
      final value = jsonDecode(payload ?? '');
      if (value is! Map || value['type'] != 'local_application') return false;
      if (value['version'] != 1 ||
          value['accountID'] is! String ||
          value['sessionKey'] is! String ||
          value['eventID'] is! String ||
          !['friend', 'group'].contains(value['kind'])) {
        return true;
      }
      final tapKey = jsonEncode(
          [value['accountID'], value['sessionKey'], value['eventID']]);
      if (!_openedTaps.add(tapKey)) return true;
      if (_openedTaps.length > 32) _openedTaps.remove(_openedTaps.first);
      _tap = (
        account: value['accountID'] as String,
        sessionKey: value['sessionKey'] as String,
        kind: value['kind'] == 'friend'
            ? ApplicationNoticeKind.friend
            : ApplicationNoticeKind.group
      );
      synchronize();
      return true;
    } catch (_) {
      return false;
    }
  }

  void invalidate() {
    _armed = null;
    _since = null;
    _tap = null;
    _epoch++;
  }

  void close() {
    invalidate();
    _closed = true;
  }
}
