import 'dart:async';

import 'package:flutter/foundation.dart';

import '../wallet_record_models.dart';
import 'wallet_journal_counterparty_source.dart';
import 'wallet_journal_entry.dart';
import 'wallet_journal_error.dart';
import 'wallet_journal_page.dart';
import 'wallet_journal_query.dart';
import 'wallet_journal_record_mapper.dart';
import 'wallet_journal_source.dart';

/// Keeps cursor ownership tied to a filter generation and login session.
class WalletJournalController extends ChangeNotifier {
  WalletJournalController({
    required this.source,
    required WalletJournalQuery query,
    required this.isCurrentAccount,
    this.counterpartySource,
  }) : _query = query.withCursor(null);

  final WalletJournalSource source;
  final bool Function() isCurrentAccount;
  final WalletJournalCounterpartySource? counterpartySource;
  WalletJournalQuery _query;
  WalletJournalQuery get query => _query;
  List<WalletRecordDto> _records = const [];
  List<WalletRecordDto> get records => _records;
  String nextCursor = '';
  bool hasMore = false;
  bool refreshing = false;
  bool loadingMore = false;
  String? error;
  String? moreError;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _headFuture;
  Future<void>? _moreFuture;
  final Set<String> _acceptedCursors = {};
  final Map<String, WalletJournalCounterpartyProfile> _counterpartyProfiles =
      {};
  final Set<String> _pendingCounterparties = {};

  bool get busy => refreshing || loadingMore;

  Future<void> updateQuery(WalletJournalQuery query) {
    final next = query.withCursor(null);
    if (mapEquals(next.toQueryParameters(), _query.toQueryParameters())) {
      return _headFuture ?? Future.value();
    }
    _query = next;
    _generation++;
    _headFuture = null;
    _moreFuture = null;
    _records = const [];
    _acceptedCursors.clear();
    _counterpartyProfiles.clear();
    _pendingCounterparties.clear();
    nextCursor = '';
    hasMore = false;
    loadingMore = false;
    refreshing = false;
    return refresh();
  }

  Future<void> refresh() {
    if (_closed || !_checkOwner()) return Future.value();
    if (_headFuture != null) return _headFuture!;
    final generation = ++_generation;
    _pendingCounterparties.clear();
    _moreFuture = null;
    loadingMore = false;
    refreshing = true;
    error = null;
    moreError = null;
    notifyListeners();
    return _headFuture = _requestHead(generation, _query);
  }

  Future<void> _requestHead(int generation, WalletJournalQuery query) async {
    try {
      final page = await Future.sync(() => source.getJournalPage(query))
          .timeout(const Duration(seconds: 6));
      if (!_accept(generation)) return;
      _validateCursor(page, '', fresh: true);
      _counterpartyProfiles.clear();
      _records = _merge(const [], page.items);
      _acceptedCursors.clear();
      if (page.hasMore) _acceptedCursors.add(page.nextCursor);
      nextCursor = page.nextCursor;
      hasMore = page.hasMore;
      unawaited(_hydrateCounterparties(generation, page.items));
    } catch (failure) {
      if (!_accept(generation)) return;
      error = _errorMessage(failure);
    } finally {
      if (!_closed && generation == _generation) {
        refreshing = false;
        _headFuture = null;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() {
    if (_closed || !_checkOwner() || refreshing || !hasMore) {
      return Future.value();
    }
    if (_moreFuture != null) return _moreFuture!;
    final generation = _generation;
    final cursor = nextCursor;
    loadingMore = true;
    moreError = null;
    notifyListeners();
    return _moreFuture = _requestMore(generation, cursor);
  }

  Future<void> _requestMore(int generation, String cursor) async {
    try {
      final page = await Future.sync(
              () => source.getJournalPage(_query.withCursor(cursor)))
          .timeout(const Duration(seconds: 6));
      if (!_accept(generation)) return;
      _validateCursor(page, cursor);
      _records = _merge(_records, page.items);
      if (page.hasMore) _acceptedCursors.add(page.nextCursor);
      nextCursor = page.nextCursor;
      hasMore = page.hasMore;
      unawaited(_hydrateCounterparties(generation, page.items));
    } catch (failure) {
      if (!_accept(generation)) return;
      moreError = _errorMessage(failure);
    } finally {
      if (!_closed && generation == _generation) {
        loadingMore = false;
        _moreFuture = null;
        notifyListeners();
      }
    }
  }

  bool _accept(int generation) {
    if (_closed || generation != _generation) return false;
    return _checkOwner();
  }

  bool _checkOwner() {
    if (isCurrentAccount()) return true;
    _generation++;
    _records = const [];
    _acceptedCursors.clear();
    _counterpartyProfiles.clear();
    _pendingCounterparties.clear();
    hasMore = false;
    nextCursor = '';
    refreshing = false;
    loadingMore = false;
    _headFuture = null;
    _moreFuture = null;
    error = null;
    moreError = null;
    notifyListeners();
    return false;
  }

  void _validateCursor(WalletJournalPage page, String requestedCursor,
      {bool fresh = false}) {
    if (page.hasMore &&
        (page.nextCursor.isEmpty ||
            page.nextCursor == requestedCursor ||
            (!fresh && _acceptedCursors.contains(page.nextCursor)))) {
      throw const FormatException('资金明细分页游标无效');
    }
  }

  List<WalletRecordDto> _merge(
      List<WalletRecordDto> previous, List<WalletJournalEntry> entries) {
    final byId = {for (final item in previous) item.id: item};
    for (final entry in entries) {
      byId[entry.id] = entry.toWalletRecord(
        counterpartyNickname:
            _counterpartyProfiles[entry.counterpartyID]?.nickname ?? '',
        counterpartyAvatarUrl:
            _counterpartyProfiles[entry.counterpartyID]?.faceURL ?? '',
      );
    }
    return List.unmodifiable(byId.values);
  }

  Future<void> _hydrateCounterparties(
      int generation, List<WalletJournalEntry> entries) async {
    final source = counterpartySource;
    if (source == null || !_accept(generation)) return;
    final userIDs = <String>{
      for (final entry in entries)
        if (const {'transfer', 'group_transfer'}.contains(entry.bizType) &&
            const {'transfer_sent', 'transfer_received'}.contains(entry.type) &&
            entry.counterpartyID.isNotEmpty &&
            (_counterpartyProfiles[entry.counterpartyID]?.nickname.isNotEmpty !=
                    true ||
                (source is WalletJournalCounterpartyProfileSource &&
                    _counterpartyProfiles[entry.counterpartyID]
                            ?.faceURL
                            .isNotEmpty !=
                        true)) &&
            !_pendingCounterparties.contains(entry.counterpartyID))
          entry.counterpartyID,
    };
    if (userIDs.isEmpty) return;
    _pendingCounterparties.addAll(userIDs);
    try {
      final profiles = await Future.sync(() async {
        if (source is WalletJournalCounterpartyProfileSource) {
          return (source as WalletJournalCounterpartyProfileSource)
              .getProfiles(userIDs);
        }
        final names = await source.getNicknames(userIDs);
        return {
          for (final entry in names.entries)
            entry.key: WalletJournalCounterpartyProfile(nickname: entry.value),
        };
      }).timeout(const Duration(seconds: 3));
      if (!_accept(generation)) return;
      var changed = false;
      for (final id in userIDs) {
        final previous = _counterpartyProfiles[id];
        final receivedName = profiles[id]?.nickname.trim() ?? '';
        final receivedFace = profiles[id]?.faceURL.trim() ?? '';
        final name =
            receivedName.isNotEmpty ? receivedName : previous?.nickname ?? '';
        final face =
            receivedFace.isNotEmpty ? receivedFace : previous?.faceURL ?? '';
        if (name.isNotEmpty || face.isNotEmpty) {
          if (previous?.nickname != name || previous?.faceURL != face) {
            _counterpartyProfiles[id] =
                WalletJournalCounterpartyProfile(nickname: name, faceURL: face);
            changed = true;
          }
        }
      }
      if (changed) {
        _records = List.unmodifiable([
          for (final record in _records)
            record.journal!.toWalletRecord(
              counterpartyNickname:
                  _counterpartyProfiles[record.journal!.counterpartyID]
                          ?.nickname ??
                      '',
              counterpartyAvatarUrl:
                  _counterpartyProfiles[record.journal!.counterpartyID]
                          ?.faceURL ??
                      '',
            ),
        ]);
        notifyListeners();
      }
    } catch (_) {
      // Profile lookup is supplementary. Keep posted ledger events available.
      if (!_closed && generation == _generation) _checkOwner();
    } finally {
      if (!_closed && generation == _generation) {
        _pendingCounterparties.removeAll(userIDs);
      }
    }
  }

  String _errorMessage(Object failure) => failure is FormatException
      ? '资金明细数据异常，请重试'
      : walletJournalErrorMessage(failure);

  @override
  void dispose() {
    _closed = true;
    _generation++;
    super.dispose();
  }
}
