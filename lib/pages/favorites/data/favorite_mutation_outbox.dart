import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_archive_retry.dart';

enum FavoriteMutationOperation {
  createMessage,
  create,
  update,
  delete,
  batchDelete,
  retryArchive,
}

/// An authenticated collection write waiting for a conclusive server result.
/// This is separate from the lightweight display cache and SDK delivery tasks.
class FavoriteMutationEntry {
  FavoriteMutationEntry({
    required this.key,
    required this.operation,
    required this.clientRequestID,
    required Map<String, dynamic> body,
    this.itemID,
    this.archiveRetryAck,
  }) : body = Map<String, dynamic>.unmodifiable(
            jsonDecode(jsonEncode(body)) as Map<String, dynamic>) {
    if (key.isEmpty ||
        !_uuid.hasMatch(clientRequestID) ||
        (body.containsKey('clientRequestID') &&
            body['clientRequestID'] != clientRequestID) ||
        ({
              FavoriteMutationOperation.update,
              FavoriteMutationOperation.delete,
              FavoriteMutationOperation.retryArchive,
            }.contains(operation) &&
            (itemID == null || itemID!.isEmpty)) ||
        (archiveRetryAck != null &&
            operation != FavoriteMutationOperation.retryArchive)) {
      throw const FormatException('Invalid favorite pending mutation');
    }
    _validateBody(this.body);
    if (archiveRetryAck != null) {
      FavoriteArchiveRetryAck.fromJson(archiveRetryAck!.toJson());
    }
  }

  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  final String key;
  final FavoriteMutationOperation operation;
  final String clientRequestID;
  final String? itemID;
  final Map<String, dynamic> body;
  final FavoriteArchiveRetryAck? archiveRetryAck;

  FavoriteMutationEntry acknowledgeArchiveRetry(FavoriteArchiveRetryAck ack) =>
      FavoriteMutationEntry(
          key: key,
          operation: operation,
          clientRequestID: clientRequestID,
          body: body,
          itemID: itemID,
          archiveRetryAck: ack);

  static void _validateBody(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String ||
            {
              'token',
              'chatToken',
              'imToken',
              'authorization',
              'Authorization',
              'uploadURL',
              'downloadURL',
              'downloads',
            }.contains(entry.key)) {
          throw const FormatException('Private credential in favorite outbox');
        }
        _validateBody(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        _validateBody(item);
      }
    }
  }

  factory FavoriteMutationEntry.fromJson(Map<String, dynamic> json) {
    final operation = FavoriteMutationOperation.values
        .where((value) => value.name == json['operation'])
        .firstOrNull;
    if (operation == null ||
        json['key'] is! String ||
        json['clientRequestID'] is! String ||
        json['body'] is! Map ||
        (json['archiveRetryAck'] != null && json['archiveRetryAck'] is! Map) ||
        (json['itemID'] != null && json['itemID'] is! String)) {
      throw const FormatException('Invalid favorite outbox record');
    }
    return FavoriteMutationEntry(
      key: json['key'] as String,
      operation: operation,
      clientRequestID: json['clientRequestID'] as String,
      itemID: json['itemID'] as String?,
      body: Map<String, dynamic>.from(json['body'] as Map),
      archiveRetryAck: json['archiveRetryAck'] == null
          ? null
          : FavoriteArchiveRetryAck.fromJson(
              Map<String, dynamic>.from(json['archiveRetryAck'] as Map)),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'operation': operation.name,
        'clientRequestID': clientRequestID,
        if (itemID != null) 'itemID': itemID,
        'body': body,
        if (archiveRetryAck != null)
          'archiveRetryAck': archiveRetryAck!.toJson(),
      };
}

abstract interface class FavoriteMutationOutboxStore {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
}

class PreferencesFavoriteMutationOutboxStore
    implements FavoriteMutationOutboxStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<bool> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

class _OutboxContents {
  _OutboxContents(this.pending, this.confirmed);
  final List<FavoriteMutationEntry> pending;
  final Map<String, String> confirmed;
}

/// Serial read-modify-write transactions preserve concurrent pending actions.
/// Replays use the original body and request UUID; no token or media grant is
/// persisted here, and each namespace belongs to one account and Chat service.
class FavoriteMutationOutbox {
  FavoriteMutationOutbox({FavoriteMutationOutboxStore? store})
      : _store = store ?? PreferencesFavoriteMutationOutboxStore();

  final FavoriteMutationOutboxStore _store;
  Future<void> _writes = Future<void>.value();

  String _storageKey(String namespace) {
    if (namespace.isEmpty) {
      throw const FormatException('Missing favorite outbox account');
    }
    return 'favorites:outbox:v1:${sha256.convert(utf8.encode(namespace))}';
  }

  Future<_OutboxContents> _read(String namespace) async {
    final raw = await _store.read(_storageKey(namespace));
    if (raw == null) return _OutboxContents([], {});
    final decoded = jsonDecode(raw);
    final values = decoded is List
        ? decoded
        : decoded is Map
            ? decoded['pending']
            : null;
    final confirmed = decoded is Map ? decoded['confirmed'] : const {};
    if (values is! List) {
      throw const FormatException('Invalid favorite outbox');
    }
    if (confirmed is! Map ||
        confirmed.entries.any((entry) =>
            entry.key is! String ||
            (entry.key as String).isEmpty ||
            entry.value is! String ||
            !FavoriteMutationEntry._uuid.hasMatch(entry.value as String))) {
      throw const FormatException('Invalid confirmed favorite operations');
    }
    final entries = values.map((value) {
      if (value is! Map) {
        throw const FormatException('Invalid favorite outbox');
      }
      return FavoriteMutationEntry.fromJson(Map<String, dynamic>.from(value));
    }).toList();
    if (entries.map((entry) => entry.key).toSet().length != entries.length) {
      throw const FormatException('Duplicate favorite outbox actions');
    }
    return _OutboxContents(entries, Map<String, String>.from(confirmed));
  }

  Future<List<FavoriteMutationEntry>> list(String namespace) async {
    await _writes;
    return List<FavoriteMutationEntry>.unmodifiable(
        (await _read(namespace)).pending);
  }

  Future<Map<String, String>> readConfirmed(String namespace) async {
    await _writes;
    return Map<String, String>.unmodifiable((await _read(namespace)).confirmed);
  }

  Future<void> _change(
      String namespace, void Function(_OutboxContents) change) {
    final write = _writes.then((_) async {
      final contents = await _read(namespace);
      change(contents);
      final saved = await _store.write(
          _storageKey(namespace),
          jsonEncode({
            'pending': contents.pending.map((entry) => entry.toJson()).toList(),
            'confirmed': contents.confirmed,
          }));
      if (!saved) throw StateError('Cannot persist favorite pending operation');
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  Future<void> put(String namespace, FavoriteMutationEntry entry) =>
      _change(namespace, (contents) {
        final entries = contents.pending;
        final index = entries.indexWhere((value) => value.key == entry.key);
        if (index >= 0) {
          final previous = entries[index];
          if (jsonEncode(previous.toJson()) != jsonEncode(entry.toJson())) {
            throw const FormatException('Favorite pending action has changed');
          }
        } else {
          entries.add(entry);
        }
      });

  Future<void> remove(String namespace, String key) => _change(namespace,
      (contents) => contents.pending.removeWhere((e) => e.key == key));

  /// Preserve the original request while the acknowledged job's detail is read.
  /// The receipt is local metadata and never changes the server request body.
  Future<void> acknowledgeArchiveRetry(String namespace, String key,
          String clientRequestID, FavoriteArchiveRetryAck ack) =>
      _change(namespace, (contents) {
        final index = contents.pending.indexWhere((entry) => entry.key == key);
        if (index < 0 ||
            contents.pending[index].clientRequestID != clientRequestID ||
            contents.pending[index].operation !=
                FavoriteMutationOperation.retryArchive) {
          throw const FormatException(
              'Cannot acknowledge a different archive retry');
        }
        final previous = contents.pending[index];
        if (previous.archiveRetryAck != null &&
            jsonEncode(previous.archiveRetryAck!.toJson()) !=
                jsonEncode(ack.toJson())) {
          throw const FormatException('Archive retry acknowledgement changed');
        }
        contents.pending[index] = previous.acknowledgeArchiveRetry(ack);
      });

  /// Atomically acknowledge the exact UUID. This proof allows stale metadata
  /// cleanup without discarding an unrelated, unconfirmed upload request.
  Future<void> complete(String namespace, String key, String clientRequestID) {
    if (key.isEmpty || !FavoriteMutationEntry._uuid.hasMatch(clientRequestID)) {
      throw const FormatException('Invalid confirmed favorite action');
    }
    return _change(namespace, (contents) {
      final pending = contents.pending.where((entry) => entry.key == key);
      if (pending.any((entry) => entry.clientRequestID != clientRequestID)) {
        throw const FormatException(
            'Cannot confirm a different favorite action');
      }
      contents.pending.removeWhere((entry) => entry.key == key);
      contents.confirmed[key] = clientRequestID;
    });
  }
}
