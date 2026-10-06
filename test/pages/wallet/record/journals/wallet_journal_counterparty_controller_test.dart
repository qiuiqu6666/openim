import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_controller.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_counterparty_source.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_page.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_query.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_source.dart';

import 'wallet_journal_entry_test.dart' show journalTestJson;

void main() {
  test('nickname-only profile retries missing avatar on later pages', () async {
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([_entry('first', user: 'user-A')],
            hasMore: true, cursor: 'next')
        : _page([_entry('second', user: 'user-A')]));
    final profiles = _RichCounterpartySource();
    profiles.respondProfiles = (_) async => {
          'user-A': WalletJournalCounterpartyProfile(
              nickname: '秋啊',
              faceURL: profiles.batches.length == 1
                  ? ''
                  : 'https://profiles.example.test/a.png'),
        };
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    expect(controller.records.single.counterpartyNickname, '秋啊');
    expect(controller.records.single.counterpartyAvatarUrl, isEmpty);
    await controller.loadMore();
    await _flush();
    expect(profiles.batches, hasLength(2));
    expect(controller.records.map((record) => record.counterpartyAvatarUrl),
        everyElement('https://profiles.example.test/a.png'));
  });

  test(
      'avatar-only profile retries missing nickname and merges later name-only data',
      () async {
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([_entry('first-A', user: 'user-A')],
            hasMore: true, cursor: 'next-page')
        : _page([_entry('second-A', user: 'user-A')]));
    final profiles = _RichCounterpartySource();
    profiles.respondProfiles = (_) async => profiles.batches.length == 1
        ? {
            'user-A': const WalletJournalCounterpartyProfile(
                faceURL: 'https://profiles.example.test/a.png')
          }
        : {
            'user-A':
                const WalletJournalCounterpartyProfile(nickname: '补充的真实昵称')
          };
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    expect(controller.records.single.counterpartyNickname, isEmpty);
    expect(controller.records.single.counterpartyAvatarUrl,
        'https://profiles.example.test/a.png');
    await controller.loadMore();
    await _flush();
    expect(profiles.batches, [
      <String>{'user-A'},
      <String>{'user-A'}
    ]);
    expect(controller.records.map((record) => record.counterpartyNickname),
        ['补充的真实昵称', '补充的真实昵称']);
    expect(controller.records.map((record) => record.counterpartyAvatarUrl), [
      'https://profiles.example.test/a.png',
      'https://profiles.example.test/a.png'
    ]);
    expect(profiles.nicknameReads, 0);
  });

  test('failed or empty nickname retry preserves an already verified avatar',
      () async {
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([_entry('first-A', user: 'user-A')],
            hasMore: true, cursor: 'page-2')
        : query.cursor == 'page-2'
            ? _page([_entry('second-A', user: 'user-A')],
                hasMore: true, cursor: 'page-3')
            : _page([_entry('third-A', user: 'user-A')]));
    final profiles = _RichCounterpartySource();
    profiles.respondProfiles = (_) async {
      if (profiles.batches.length == 1) {
        return {
          'user-A': const WalletJournalCounterpartyProfile(
              faceURL: 'https://profiles.example.test/a.png')
        };
      }
      if (profiles.batches.length == 2) {
        throw StateError('Synthetic profile failure');
      }
      return {
        'user-A':
            const WalletJournalCounterpartyProfile(nickname: '   ', faceURL: '')
      };
    };
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    await controller.loadMore();
    await _flush();
    await controller.loadMore();
    await _flush();
    expect(profiles.batches, hasLength(3));
    expect(controller.records, hasLength(3));
    expect(
        controller.records
            .every((record) => record.counterpartyNickname.isEmpty),
        isTrue);
    expect(
        controller.records.every((record) =>
            record.counterpartyAvatarUrl ==
            'https://profiles.example.test/a.png'),
        isTrue);
    expect(controller.error, isNull);
    expect(controller.moreError, isNull);
  });
  test('rich source makes one profile read and reuses avatars across pages',
      () async {
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([_entry('first-A', user: 'user-A')],
            hasMore: true, cursor: 'next-page')
        : _page([
            _entry('second-A', user: 'user-A'),
            _entry('new-B', user: 'user-B')
          ]));
    final profiles = _RichCounterpartySource()
      ..respondProfiles = (users) async => {
            for (final user in users)
              user: WalletJournalCounterpartyProfile(
                  nickname: '$user 昵称',
                  faceURL: 'https://profiles.example.test/$user.png'),
          };
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    await controller.loadMore();
    await _flush();
    expect(profiles.batches, [
      <String>{'user-A'},
      <String>{'user-B'}
    ]);
    expect(profiles.nicknameReads, 0);
    expect(controller.records.map((record) => record.counterpartyAvatarUrl), [
      'https://profiles.example.test/user-A.png',
      'https://profiles.example.test/user-A.png',
      'https://profiles.example.test/user-B.png',
    ]);
    expect(controller.records.map((record) => record.counterpartyNickname),
        ['user-A 昵称', 'user-A 昵称', 'user-B 昵称']);
  });

  test('late avatars update all pending rows without blocking ledger reads',
      () async {
    final pending = Completer<Map<String, WalletJournalCounterpartyProfile>>();
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([_entry('first-A', user: 'user-A')],
            hasMore: true, cursor: 'next-page')
        : _page([_entry('second-A', user: 'user-A')]));
    final profiles = _RichCounterpartySource()
      ..respondProfiles = (_) => pending.future;
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await controller.loadMore();
    expect(
        controller.records
            .every((record) => record.counterpartyAvatarUrl.isEmpty),
        isTrue);
    expect(profiles.batches, [
      <String>{'user-A'}
    ]);
    pending.complete({
      'user-A': const WalletJournalCounterpartyProfile(
          nickname: '阿秋', faceURL: ' https://profiles.example.test/a.png '),
      'unrequested': const WalletJournalCounterpartyProfile(
          nickname: '无关资料', faceURL: 'https://profiles.example.test/other.png'),
    });
    await _flush();
    expect(controller.records.map((record) => record.counterpartyAvatarUrl), [
      'https://profiles.example.test/a.png',
      'https://profiles.example.test/a.png'
    ]);
    expect(controller.records.map((record) => record.counterpartyNickname),
        ['阿秋', '阿秋']);
    expect(profiles.nicknameReads, 0);
  });

  test('old filter avatars cannot overwrite the current generation', () async {
    final previous = Completer<Map<String, WalletJournalCounterpartyProfile>>();
    final current = Completer<Map<String, WalletJournalCounterpartyProfile>>();
    final journal = _JournalSource((query) async => _page([
          _entry(query.currency == null ? 'old-A' : 'current-A',
              user: 'user-A', currency: query.currency ?? 'USDT'),
        ]));
    final profiles = _RichCounterpartySource();
    profiles.respondProfiles =
        (_) => profiles.batches.length == 1 ? previous.future : current.future;
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await controller.updateQuery(const WalletJournalQuery(currency: 'BI99'));
    current.complete({
      'user-A': const WalletJournalCounterpartyProfile(
          nickname: '当前昵称',
          faceURL: 'https://profiles.example.test/current.png')
    });
    await _flush();
    previous.complete({
      'user-A': const WalletJournalCounterpartyProfile(
          nickname: '旧昵称', faceURL: 'https://profiles.example.test/old.png')
    });
    await _flush();
    expect(controller.records.single.id, 'current-A');
    expect(controller.records.single.counterpartyNickname, '当前昵称');
    expect(controller.records.single.counterpartyAvatarUrl,
        'https://profiles.example.test/current.png');
  });

  test('replaced owner rejects a pending rich profile and its avatar cache',
      () async {
    var currentOwner = true;
    final pending = Completer<Map<String, WalletJournalCounterpartyProfile>>();
    final journal = _JournalSource(
        (_) async => _page([_entry('old-owner', user: 'user-A')]));
    final profiles = _RichCounterpartySource()
      ..respondProfiles = (_) => pending.future;
    final controller =
        _controller(journal, profiles, isCurrentAccount: () => currentOwner);
    await controller.refresh();
    currentOwner = false;
    pending.complete({
      'user-A': const WalletJournalCounterpartyProfile(
          nickname: '旧账号昵称', faceURL: 'https://profiles.example.test/old.png')
    });
    await _flush();
    expect(controller.records, isEmpty);
    expect(controller.error, isNull);
  });

  test('an unavailable rich profile never hides posted ledger events',
      () async {
    final journal = _JournalSource(
        (_) async => _page([_entry('retained-A', user: 'user-A')]));
    final profiles = _RichCounterpartySource()
      ..respondProfiles = (_) async => throw StateError('Synthetic offline');
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    expect(controller.records.single.id, 'retained-A');
    expect(controller.records.single.counterpartyNickname, isEmpty);
    expect(controller.records.single.counterpartyAvatarUrl, isEmpty);
    expect(controller.error, isNull);
    expect(profiles.nicknameReads, 0);
  });
  test('nickname reads batch only transfer counterparties and deduplicate IDs',
      () async {
    final journal = _JournalSource((_) async => _page([
          _entry('send-A', user: 'user-A'),
          _entry('receive-A', user: 'user-A', income: true),
          _entry('group-B', user: 'user-B', bizType: 'group_transfer'),
          _entry('no-counterparty'),
          _entry('adjustment-C', user: 'user-C', bizType: 'admin_adjust'),
          _entry('packet-C', user: 'user-C', bizType: 'packet_normal'),
        ]));
    final profiles = _CounterpartySource()
      ..respond = (_) async => {'user-A': '阿秋', 'user-B': '朋友B'};
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    expect(profiles.batches, [
      {'user-A', 'user-B'}
    ]);
    final names = {
      for (final record in controller.records)
        record.id: record.counterpartyNickname,
    };
    expect(names, {
      'send-A': '阿秋',
      'receive-A': '阿秋',
      'group-B': '朋友B',
      'no-counterparty': '',
      'adjustment-C': '',
      'packet-C': '',
    });
    expect(controller.error, isNull);
  });

  test('pending names do not block ledger pages or duplicate their SDK read',
      () async {
    final names = Completer<Map<String, String>>();
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([_entry('first-A', user: 'user-A')],
            hasMore: true, cursor: 'next-page')
        : _page([
            _entry('first-A', user: 'user-A'),
            _entry('second-A', user: 'user-A'),
          ]));
    final profiles = _CounterpartySource()..respond = (_) => names.future;
    final controller = _controller(journal, profiles);
    await controller.refresh().timeout(const Duration(seconds: 1));
    expect(controller.refreshing, isFalse);
    expect(controller.records.single.id, 'first-A');
    expect(controller.records.single.counterpartyNickname, isEmpty);
    await controller.loadMore().timeout(const Duration(seconds: 1));
    expect(controller.loadingMore, isFalse);
    expect(
        controller.records.map((record) => record.id), ['first-A', 'second-A']);
    expect(profiles.batches, [
      {'user-A'}
    ]);
    names.complete({'user-A': '阿秋'});
    await _flush();
    expect(controller.records.map((record) => record.counterpartyNickname),
        ['阿秋', '阿秋']);
    expect(controller.error, isNull);
    expect(controller.moreError, isNull);
  });

  test('resolved profiles are reused across pages and repeated journal IDs',
      () async {
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([_entry('first-A', user: 'user-A')],
            hasMore: true, cursor: 'next-page')
        : _page([
            _entry('first-A', user: 'user-A'),
            _entry('second-A', user: 'user-A'),
            _entry('new-B', user: 'user-B'),
          ]));
    final profiles = _CounterpartySource()
      ..respond = (users) async => {
            for (final user in users) user: user == 'user-A' ? '阿秋' : '朋友B',
          };
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    await controller.loadMore();
    await _flush();
    expect(profiles.batches, [
      {'user-A'},
      {'user-B'},
    ]);
    expect(controller.records.map((record) => record.id).toSet(), hasLength(3));
    expect(controller.records.map((record) => record.counterpartyNickname),
        ['阿秋', '阿秋', '朋友B']);
  });

  test('a failed profile read retains ledger events and can retry next page',
      () async {
    var fail = true;
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([_entry('first-A', user: 'user-A')],
            hasMore: true, cursor: 'next-page')
        : _page([_entry('second-A', user: 'user-A')]));
    final profiles = _CounterpartySource()
      ..respond = (_) async {
        if (fail) throw StateError('SDK profile test failure');
        return {'user-A': '阿秋'};
      };
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    expect(controller.records.single.id, 'first-A');
    expect(controller.records.single.counterpartyNickname, isEmpty);
    expect(controller.records.single.journal!.amount, '8');
    expect(controller.error, isNull);
    expect(controller.moreError, isNull);
    fail = false;
    await controller.loadMore();
    await _flush();
    expect(profiles.batches, [
      {'user-A'},
      {'user-A'},
    ]);
    expect(controller.records.map((record) => record.counterpartyNickname),
        ['阿秋', '阿秋']);
    expect(controller.records, hasLength(2));
  });

  test('missing or empty nicknames remain unresolved and may retry next page',
      () async {
    final journal = _JournalSource((query) async => query.cursor == null
        ? _page([
            _entry('first-A', user: 'user-A'),
            _entry('first-B', user: 'user-B'),
          ], hasMore: true, cursor: 'next-page')
        : _page([
            _entry('second-A', user: 'user-A'),
            _entry('second-B', user: 'user-B'),
          ]));
    final profiles = _CounterpartySource();
    profiles.respond = (_) async => profiles.batches.length == 1
        ? {'user-A': '   '}
        : {'user-A': '阿秋', 'user-B': '朋友B'};
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    expect(
        controller.records.every((item) => item.counterpartyNickname.isEmpty),
        isTrue);
    await controller.loadMore();
    await _flush();
    expect(profiles.batches, [
      {'user-A', 'user-B'},
      {'user-A', 'user-B'},
    ]);
    expect(controller.records.map((record) => record.counterpartyNickname),
        ['阿秋', '朋友B', '阿秋', '朋友B']);
  });

  test('profile responses from an old filter cannot hydrate the new generation',
      () async {
    final previous = Completer<Map<String, String>>();
    final current = Completer<Map<String, String>>();
    final journal = _JournalSource((query) async => _page([
          _entry(query.currency == null ? 'old-A' : 'current-A',
              user: 'user-A', currency: query.currency ?? 'USDT'),
        ]));
    final profiles = _CounterpartySource();
    profiles.respond =
        (_) => profiles.batches.length == 1 ? previous.future : current.future;
    final controller = _controller(journal, profiles);
    await controller.refresh();
    await _flush();
    await controller.updateQuery(const WalletJournalQuery(currency: 'BI99'));
    await _flush();
    expect(profiles.batches, hasLength(2));
    current.complete({'user-A': '当前昵称'});
    await _flush();
    previous.complete({'user-A': '旧昵称'});
    await _flush();
    expect(controller.records.single.id, 'current-A');
    expect(controller.records.single.counterpartyNickname, '当前昵称');
  });

  test('profile responses cannot publish into a replaced login session',
      () async {
    var sameAccount = true;
    final names = Completer<Map<String, String>>();
    final journal = _JournalSource(
        (_) async => _page([_entry('old-owner', user: 'user-A')]));
    final profiles = _CounterpartySource()..respond = (_) => names.future;
    final controller =
        _controller(journal, profiles, isCurrentAccount: () => sameAccount);
    await controller.refresh();
    sameAccount = false;
    names.complete({'user-A': '旧账号昵称'});
    await _flush();
    expect(controller.records, isEmpty);
    expect(controller.error, isNull);
    expect(journal.queries, hasLength(1));
  });

  test('a profile response after disposal never emits another notification',
      () async {
    final names = Completer<Map<String, String>>();
    final journal =
        _JournalSource((_) async => _page([_entry('closed', user: 'user-A')]));
    final profiles = _CounterpartySource()..respond = (_) => names.future;
    final controller = WalletJournalController(
        source: journal,
        query: const WalletJournalQuery(),
        isCurrentAccount: () => true,
        counterpartySource: profiles);
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.refresh();
    final beforeClose = notifications;
    controller.dispose();
    names.complete({'user-A': '迟回昵称'});
    await _flush();
    expect(notifications, beforeClose);
    expect(controller.records.single.counterpartyNickname, isEmpty);
  });

  test('the optional profile source leaves existing ledger-only clients usable',
      () async {
    final journal = _JournalSource(
        (_) async => _page([_entry('without-source', user: 'user-A')]));
    final controller = WalletJournalController(
        source: journal,
        query: const WalletJournalQuery(),
        isCurrentAccount: () => true);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.records.single.id, 'without-source');
    expect(controller.records.single.counterpartyNickname, isEmpty);
    expect(controller.error, isNull);
  });
}

WalletJournalController _controller(
    _JournalSource journal, _CounterpartySource profiles,
    {bool Function()? isCurrentAccount}) {
  final controller = WalletJournalController(
      source: journal,
      query: const WalletJournalQuery(),
      isCurrentAccount: isCurrentAccount ?? () => true,
      counterpartySource: profiles);
  addTearDown(controller.dispose);
  return controller;
}

class _JournalSource implements WalletJournalSource {
  _JournalSource(this.respond);
  final Future<WalletJournalPage> Function(WalletJournalQuery query) respond;
  final List<WalletJournalQuery> queries = [];

  @override
  Future<WalletJournalPage> getJournalPage(WalletJournalQuery query) {
    queries.add(query);
    return respond(query);
  }
}

class _CounterpartySource implements WalletJournalCounterpartySource {
  final List<Set<String>> batches = [];
  Future<Map<String, String>> Function(Set<String> users)? respond;

  @override
  Future<Map<String, String>> getNicknames(Set<String> userIDs) {
    final users = Set<String>.unmodifiable(userIDs);
    batches.add(users);
    return respond?.call(users) ?? Future.value({});
  }
}

class _RichCounterpartySource extends _CounterpartySource
    implements WalletJournalCounterpartyProfileSource {
  Future<Map<String, WalletJournalCounterpartyProfile>> Function(
      Set<String> users)? respondProfiles;
  int nicknameReads = 0;

  @override
  Future<Map<String, String>> getNicknames(Set<String> userIDs) {
    nicknameReads++;
    throw StateError('Rich source must not also make a nickname request');
  }

  @override
  Future<Map<String, WalletJournalCounterpartyProfile>> getProfiles(
      Set<String> userIDs) {
    final users = Set<String>.unmodifiable(userIDs);
    batches.add(users);
    return respondProfiles?.call(users) ?? Future.value({});
  }
}

WalletJournalEntry _entry(String id,
    {String user = '',
    bool income = false,
    String bizType = 'transfer',
    String currency = 'USDT'}) {
  final transfer = bizType == 'transfer' || bizType == 'group_transfer';
  return WalletJournalEntry.fromJson(journalTestJson(id: id)
    ..addAll({
      'currency': currency,
      'bizType': bizType,
      'type': transfer
          ? (income ? 'transfer_received' : 'transfer_sent')
          : (bizType == 'packet_normal' ? 'packet_settlement' : 'admin_adjust'),
      'title': transfer ? (income ? '收到转账' : '转账支出') : '其他资金事件',
      'direction': income ? 'income' : 'expense',
      'availableDelta':
          bizType == 'packet_normal' ? '0' : (income ? '8' : '-8'),
      'frozenDelta': bizType == 'packet_normal' ? '-8' : '0',
      'assetDelta': income ? '8' : '-8',
      'counterpartyID': user,
    }));
}

WalletJournalPage _page(List<WalletJournalEntry> items,
        {bool hasMore = false, String cursor = ''}) =>
    WalletJournalPage(
        items: items, limit: 20, hasMore: hasMore, nextCursor: cursor);

Future<void> _flush() => Future<void>.delayed(Duration.zero);
