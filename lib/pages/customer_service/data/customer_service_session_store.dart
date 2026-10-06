import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'customer_service_api.dart';
import 'customer_service_session.dart';

class CustomerServiceSessionCancelled implements Exception {
  const CustomerServiceSessionCancelled();
}

/// A page-owned store. The caller's predicate must capture the account/session
/// generation, so an old page cannot create or publish a new account's session.
class CustomerServiceSessionStore {
  CustomerServiceSessionStore({
    required this.api,
    required this.accountId,
    required this.isActive,
    Future<SharedPreferences> Function()? preferences,
    String Function()? identifierFactory,
  })  : _preferences = preferences ?? SharedPreferences.getInstance,
        _identifierFactory = identifierFactory ?? const Uuid().v4;

  final CustomerServiceApi api;
  final String accountId;
  final bool Function() isActive;
  final Future<SharedPreferences> Function() _preferences;
  final String Function() _identifierFactory;
  Future<CustomerServiceSession>? _pending;
  CustomerServiceSession? _ready;
  int _generation = 0;
  bool _disposed = false;

  String get storageKey {
    final scope = jsonEncode([
      accountId.trim().isEmpty ? 'guest' : 'account:${accountId.trim()}',
      api.config.normalizedBaseUrl,
      api.config.inboxIdentifier.trim(),
    ]);
    return 'customer_service_session_v1_${base64Url.encode(utf8.encode(scope))}';
  }

  Future<CustomerServiceSession> ensure({
    required String name,
    String avatarUrl = '',
  }) async {
    final generation = _generation;
    _check(generation);
    final ready = _ready;
    if (ready != null) return ready;
    final pending = _pending;
    if (pending != null) return pending;
    final work = _loadOrCreate(generation, name, avatarUrl);
    _pending = work;
    try {
      return await work;
    } finally {
      if (identical(_pending, work)) _pending = null;
    }
  }

  Future<CustomerServiceSession> _loadOrCreate(
      int generation, String name, String avatarUrl) async {
    final prefs = await _preferences();
    _check(generation);
    final key = storageKey;
    var record = _read(prefs.getString(key));
    if (record.identifier.isEmpty) {
      record = _Record(identifier: _identifierFactory());
      await _save(prefs, key, record, generation);
    }

    if (record.sourceId.isEmpty || record.pubsubToken.isEmpty) {
      _check(generation);
      final contact = await api.createContact(
          identifier: record.identifier, name: name, avatarUrl: avatarUrl);
      _check(generation);
      record = _Record(
        identifier: record.identifier,
        sourceId: contact.sourceId,
        pubsubToken: contact.pubsubToken,
      );
      // Persist the contact before creating its conversation: a retry after
      // conversation creation fails reuses the real contact.
      await _save(prefs, key, record, generation);
    } else {
      _check(generation);
      try {
        await api.updateContact(
            sourceId: record.sourceId, name: name, avatarUrl: avatarUrl);
      } catch (_) {
        // A transient profile-update failure does not discard a live session.
      }
      _check(generation);
    }

    if (record.conversationId.isEmpty) {
      _check(generation);
      final conversationId = await api.createConversation(record.sourceId);
      _check(generation);
      record = _Record(
        identifier: record.identifier,
        sourceId: record.sourceId,
        pubsubToken: record.pubsubToken,
        conversationId: conversationId,
      );
      await _save(prefs, key, record, generation);
    }
    _check(generation);
    return _ready = CustomerServiceSession(
      identifier: record.identifier,
      sourceId: record.sourceId,
      pubsubToken: record.pubsubToken,
      conversationId: record.conversationId,
    );
  }

  Future<void> _save(SharedPreferences prefs, String key, _Record record,
      int generation) async {
    _check(generation);
    final saved = await prefs.setString(key, jsonEncode(record.toJson()));
    _check(generation);
    if (!saved) throw StateError('Customer service session could not be saved');
  }

  void _check(int generation) {
    if (_disposed || generation != _generation || !isActive()) {
      throw const CustomerServiceSessionCancelled();
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _ready = null;
  }
}

class _Record {
  const _Record({
    this.identifier = '',
    this.sourceId = '',
    this.pubsubToken = '',
    this.conversationId = '',
  });
  final String identifier, sourceId, pubsubToken, conversationId;

  Map<String, String> toJson() => {
        'identifier': identifier,
        'sourceId': sourceId,
        'pubsubToken': pubsubToken,
        'conversationId': conversationId,
      };
}

_Record _read(String? raw) {
  if (raw == null) return const _Record();
  try {
    final json = jsonDecode(raw);
    if (json is! Map) return const _Record();
    String text(String key) => json[key]?.toString().trim() ?? '';
    final identifier = text('identifier');
    if (identifier.isEmpty) return const _Record();
    return _Record(
      identifier: identifier,
      sourceId: text('sourceId'),
      pubsubToken: text('pubsubToken'),
      conversationId: text('conversationId'),
    );
  } catch (_) {
    return const _Record();
  }
}
