import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'voice_to_text_service.dart';

typedef VoiceMessageTranscriber = Future<String> Function(Message message,
    {CancelToken? cancelToken});

/// One controller per conversation keeps jobs independent of message rebuilds.
/// [persist] receives a patch. The conversation's shared localEx writer merges
/// it with the freshest message state, preserving concurrent voiceHeard writes.
class VoiceTranscriptionController extends ChangeNotifier {
  VoiceTranscriptionController({
    VoiceToTextService? service,
    VoiceMessageTranscriber? transcribe,
    this.persist,
    DateTime Function()? now,
  })  : assert(service == null || transcribe == null),
        _now = now ?? DateTime.now,
        _service =
            transcribe == null ? (service ?? VoiceToTextService()) : null,
        _ownsService = service == null && transcribe == null {
    _transcribe = transcribe ?? _service!.transcribeMessage;
  }

  final Future<void> Function(Message, Map<String, dynamic>)? persist;
  final VoiceToTextService? _service;
  final bool _ownsService;
  final DateTime Function() _now;
  late final VoiceMessageTranscriber _transcribe;
  final Map<String, VoiceTranscriptionState> _states = {};
  final Map<String, _VoiceTranscriptionJob> _jobs = {};
  final Map<String, Message> _privateMessages = {};
  final Map<String, Timer> _expiryTimers = {};
  final Map<String, DateTime> _expiryDeadlines = {};
  bool _disposed = false;

  static Map<String, dynamic> _extra(Message message) {
    try {
      final value = jsonDecode(message.localEx ?? '{}');
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    return {};
  }

  static VoiceTranscriptionState _persistedState(Message message) {
    // Private transcripts exist only while this conversation is open.
    if (message.attachedInfoElem?.isPrivateChat == true) {
      return const VoiceTranscriptionState();
    }
    final extra = _extra(message);
    final text = extra['voiceToText'];
    return VoiceTranscriptionState(
      text: text is String && text.trim().isNotEmpty ? text : null,
      expanded: extra['voiceToTextDisplayState'] != 'collapsed',
    );
  }

  bool canTranscribe(Message message) =>
      message.isVoiceType &&
      message.soundElem != null &&
      (message.burnDeadline == null || message.burnDeadline!.isAfter(_now()));

  VoiceTranscriptionState stateFor(Message message) {
    if (_disposed) return const VoiceTranscriptionState();
    final id = message.clientMsgID;
    if (id != null && id.isNotEmpty) _watchExpiry(message, id);
    if (!canTranscribe(message)) return const VoiceTranscriptionState();
    return _states[id] ?? _persistedState(message);
  }

  void _cancelExpiry(String id) {
    _expiryTimers.remove(id)?.cancel();
    _expiryDeadlines.remove(id);
  }

  void _watchExpiry(Message message, String id) {
    if (message.attachedInfoElem?.isPrivateChat != true) {
      _privateMessages.remove(id);
      _cancelExpiry(id);
      return;
    }
    _privateMessages[id] = message;
    if (!canTranscribe(message)) {
      // stateFor is called during build, so it must not notify synchronously.
      _remove(id, notify: false);
      return;
    }
    final deadline = message.burnDeadline;
    if (deadline == null) {
      _cancelExpiry(id);
      return;
    }
    if (_expiryDeadlines[id] == deadline) return;
    _cancelExpiry(id);
    _expiryDeadlines[id] = deadline;
    _expiryTimers[id] = Timer(deadline.difference(_now()), () {
      _expiryTimers.remove(id);
      _expiryDeadlines.remove(id);
      if (_disposed) return;
      final latest = _privateMessages[id];
      if (latest == null) return;
      if (!canTranscribe(latest)) {
        remove(id);
      } else {
        // A read receipt can change the deadline while recognition is pending.
        _watchExpiry(latest, id);
      }
    });
  }

  Future<void> transcribe(Message message) {
    if (_disposed) return Future.value();
    final id = message.clientMsgID;
    if (id == null || id.isEmpty) return Future.value();
    _watchExpiry(message, id);
    if (!canTranscribe(message)) return Future.value();
    final running = _jobs[id];
    if (running != null) return running.future;
    final previous = stateFor(message);
    if (previous.hasText) return Future.value();
    final job = _VoiceTranscriptionJob();
    _jobs[id] = job;
    _states[id] = const VoiceTranscriptionState(loading: true);
    // Assign the future before notifying, so listeners can safely deduplicate.
    job.future = Future.microtask(() => _run(message, id, job));
    notifyListeners();
    return job.future;
  }

  bool _isCurrent(String id, _VoiceTranscriptionJob job, Message message) {
    if (_disposed || !identical(_jobs[id], job) || job.token.isCancelled) {
      return false;
    }
    final latest = _privateMessages[id] ?? message;
    if (!canTranscribe(latest)) {
      remove(id);
      return false;
    }
    _watchExpiry(latest, id);
    return true;
  }

  Future<void> _run(
      Message message, String id, _VoiceTranscriptionJob job) async {
    if (!_isCurrent(id, job, message)) return;
    try {
      final text = (await _transcribe(message, cancelToken: job.token)).trim();
      if (!_isCurrent(id, job, message)) return;
      if (text.isEmpty) {
        throw const VoiceToTextException('voiceToTextEmpty');
      }
      _states[id] = VoiceTranscriptionState(text: text);
      notifyListeners();
      await _write(message, {
        'voiceToText': text,
        'voiceToTextDisplayState': 'expanded',
      });
    } catch (error) {
      if (!_isCurrent(id, job, message)) return;
      if (error is DioException && CancelToken.isCancel(error)) {
        _states.remove(id);
      } else {
        final text = _states[id]?.text;
        _states[id] = VoiceTranscriptionState(
          text: text,
          error: error is VoiceToTextException
              ? error.messageKey
              : 'voiceToTextFailed',
          expanded: _states[id]?.expanded ?? true,
        );
      }
      notifyListeners();
    } finally {
      if (identical(_jobs[id], job)) _jobs.remove(id);
      job.token.cancel();
    }
  }

  /// Cached text changes only its display state. Retry starts another job after
  /// a failure; repeated taps during a request share the original job.
  Future<void> toggle(Message message) async {
    if (_disposed) return;
    final id = message.clientMsgID;
    if (id == null || id.isEmpty) return;
    _watchExpiry(message, id);
    if (!canTranscribe(message)) return;
    final state = stateFor(message);
    if (!state.hasText) return transcribe(message);
    final expanded = !state.expanded;
    _states[id] = VoiceTranscriptionState(
      text: state.text,
      expanded: expanded,
    );
    notifyListeners();
    try {
      await _write(message, {
        'voiceToText': state.text,
        'voiceToTextDisplayState': expanded ? 'expanded' : 'collapsed',
      });
    } catch (_) {
      // Keep the successfully recognized text available when local SDK storage
      // is temporarily unavailable. A later toggle retries persistence.
    }
  }

  Future<void> _write(Message message, Map<String, dynamic> patch) async {
    if (_disposed || message.attachedInfoElem?.isPrivateChat == true) return;
    final callback = persist;
    if (callback != null) {
      await callback(message, patch);
    } else {
      // Never merge a snapshot captured before the recognition request.
      message.localEx = jsonEncode(_extra(message)..addAll(patch));
    }
  }

  void remove(String id) {
    _remove(id, notify: true);
  }

  void _remove(String id, {required bool notify}) {
    _jobs.remove(id)?.token.cancel();
    final removed = _states.remove(id);
    _privateMessages.remove(id);
    _cancelExpiry(id);
    if (notify && !_disposed && removed != null) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in _jobs.values) {
      job.token.cancel();
    }
    _jobs.clear();
    _states.clear();
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    _expiryDeadlines.clear();
    _privateMessages.clear();
    if (_ownsService) _service?.dispose();
    super.dispose();
  }
}

class _VoiceTranscriptionJob {
  final CancelToken token = CancelToken();
  late final Future<void> future;
}
