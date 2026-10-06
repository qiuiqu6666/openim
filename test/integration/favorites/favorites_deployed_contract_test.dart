import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in: use a dedicated test account. Credentials are provided only through
/// the process environment. The test cleans only records it creates and never
/// sends an OpenIM message or persists a token or signed URL.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final token = Platform.environment['FAVORITES_LIVE_CHAT_TOKEN'];
  final owner = Platform.environment['FAVORITES_LIVE_USER_ID'];
  final base = Platform.environment['FAVORITES_LIVE_BASE_URL'];
  final enabled = token?.isNotEmpty == true &&
      owner?.isNotEmpty == true &&
      base?.isNotEmpty == true;
  if (enabled) {
    // Flutter's default test binding substitutes HTTP with a 400 response.
    // This separately opted-in test deliberately exercises the deployed API.
    HttpOverrides.global = null;
  }

  test('deployed contract: read-only list, detail and changes', () async {
    final client = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15)));
    final api =
        FavoriteApi(client: client, baseUrl: base, tokenProvider: () => token);
    try {
      expect((await api.getQuota()).available, isTrue);
      final page = await api.list();
      for (final item in page.items.take(3)) {
        final detail = await api.getDetail(item.id);
        expect(detail.id, item.id);
        if (detail.status != FavoriteStatus.ready) {
          expect(detail.canSend, isFalse);
        }
      }
      final changes = await api.changes(updatedAfter: page.syncAt);
      expect(changes.syncAt, greaterThanOrEqualTo(page.syncAt));
    } finally {
      client.close(force: true);
    }
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 1)));

  test('deployed contract: note/link writes, reads, changes and prepare',
      () async {
    SharedPreferences.setMockInitialValues({});
    final client = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15)));
    final api =
        FavoriteApi(client: client, baseUrl: base, tokenProvider: () => token);
    final repository = FavoriteRepository(
        api: api, userIDProvider: () => owner, cacheEnabled: false);
    final marker = 'favorites-smoke-${FavoriteApi.newRequestID()}';
    final owned = <String, int>{};
    try {
      expect((await api.getQuota()).available, isTrue);
      final baseline = (await api.list()).syncAt;
      final note = await repository.createNote(marker, title: marker);
      owned[note.id] = note.version;
      expect(note.kind, FavoriteKind.note);
      expect(note.status, FavoriteStatus.ready);
      expect(note.coverAssetID, isNull);
      expect(note.blocks.single.id, 'b1');
      final link = await repository
          .createLink('https://example.invalid/favorites-smoke', title: marker);
      owned[link.id] = link.version;
      expect(link.kind, FavoriteKind.link);
      expect(link.blocks.single.id, 'b1');

      final detail = await repository.getDetail(note.id);
      expect(detail.text, marker);
      final edited = await repository.updateNote(note.id, '$marker edited',
          expectedVersion: detail.version);
      owned[note.id] = edited.version;
      expect(edited.version, greaterThan(note.version));
      expect(edited.text, '$marker edited');
      await repository.refresh(query: marker);
      expect(repository.items.map((item) => item.id), containsAll(owned.keys));
      expect(repository.error, isNull);

      final changes = await api.changes(updatedAfter: baseline);
      expect(changes.events.map((event) => event.id), containsAll(owned.keys));
      final prepared = await api.prepareForSend(note.id,
          expectedContentRevision: edited.contentRevision!,
          sendAttemptID: FavoriteApi.newRequestID(),
          clientRequestID: FavoriteApi.newRequestID());
      expect(prepared.sendContent.text, '$marker edited');
      expect(prepared.sendContent.blocks.single.id, 'b1');
      expect(prepared.downloads, isEmpty);
      expect(prepared.contentRevision, edited.contentRevision);
      expect(prepared.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    } finally {
      // A cleanup failure is a failed test, not a suppressed success report.
      try {
        for (final entry in owned.entries) {
          await api.delete(entry.key,
              expectedVersion: entry.value,
              clientRequestID: FavoriteApi.newRequestID());
        }
      } finally {
        repository.dispose();
        client.close(force: true);
      }
    }
  }, skip: !enabled, timeout: const Timeout(Duration(minutes: 2)));
}
