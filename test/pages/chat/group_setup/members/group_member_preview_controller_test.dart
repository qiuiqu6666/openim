import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_source.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity_info.dart';
import 'package:openim/pages/chat/group_setup/members/group_member_preview_controller.dart';

const _group = 'group';

Map<String, dynamic> _rows(List<Map<String, dynamic>> members) => {
      'members': members,
    };

Map<String, dynamic> _member(String id, {int role = GroupRoleLevel.member}) => {
      'groupID': _group,
      'userID': id,
      'nickname': id,
      'roleLevel': role,
    };

class _Harness {
  _Harness({Duration retryDelay = Duration.zero}) {
    controller = GroupMemberPreviewController(
      source: GroupMemberIdentitySource(
        poster: (_, __, ___) {
          final reply = Completer<Map<String, dynamic>>();
          replies.add(reply);
          return reply.future;
        },
        currentUserID: () => 'viewer',
        sdkUserID: () => 'viewer',
        currentToken: () => 'im-token',
        baseURL: () => 'https://preview.test',
      ),
      retryDelay: retryDelay,
    );
  }

  final replies = <Completer<Map<String, dynamic>>>[];
  late GroupMemberPreviewController controller;
  bool current = true;

  Future<void> refresh({Object scope = 'permission-1'}) => controller.refresh(
        groupID: _group,
        scope: scope,
        isCurrent: () => current,
      );

  Future<void> close() async {
    controller.dispose();
    for (final reply in replies) {
      if (!reply.isCompleted) reply.complete(_rows([]));
    }
    await _drain();
  }
}

Future<void> _drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.close());

  test('same permission scope returns one shared flight', () async {
    final first = harness.refresh();
    final second = harness.refresh();
    expect(identical(first, second), isTrue);
    expect(harness.replies, hasLength(1));
    harness.replies.single.complete(_rows([_member('peer')]));
    await first;
    expect(harness.controller.members.single.userID, 'peer');
  });

  test('a changed scope immediately clears the previous permitted members',
      () async {
    final first = harness.refresh();
    harness.replies.single.complete(_rows([
      {..._member('peer'), 'account': 'previous-account'},
    ]));
    await first;
    expect(
        (harness.controller.members.single as GroupMemberIdentityInfo).account,
        'previous-account');
    final next = harness.refresh(scope: 'permission-2');
    expect(harness.controller.members, isEmpty);
    harness.replies.last.completeError(DioException(
      requestOptions: RequestOptions(path: '/group/get_group_member_list'),
      type: DioExceptionType.badResponse,
    ));
    await next;
    expect(harness.controller.members, isEmpty);
    expect(harness.controller.failed.value, isTrue);
  });

  test('empty first page retries once and then publishes members', () async {
    final flight = harness.refresh();
    harness.replies.single.complete(_rows([]));
    await _drain();
    expect(harness.replies, hasLength(2));
    expect(harness.controller.loading.value, isTrue);
    expect(harness.controller.failed.value, isFalse);
    harness.replies.last.complete(_rows([_member('peer')]));
    await flight;
    expect(harness.controller.loading.value, isFalse);
    expect(harness.controller.failed.value, isFalse);
    expect(harness.controller.members.single.userID, 'peer');
  });

  test('two empty pages end with an explicit failure and no retry loop',
      () async {
    final flight = harness.refresh();
    harness.replies.single.complete(_rows([]));
    await _drain();
    harness.replies.last.complete(_rows([]));
    await flight;
    await _drain();
    expect(harness.replies, hasLength(2));
    expect(harness.controller.loading.value, isFalse);
    expect(harness.controller.failed.value, isTrue);
    expect(harness.controller.members, isEmpty);
  });

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
  ]) {
    test('$type retries once without clearing the loading state', () async {
      final flight = harness.refresh();
      harness.replies.single.completeError(DioException(
        requestOptions: RequestOptions(path: '/group/get_group_member_list'),
        type: type,
      ));
      await _drain();
      expect(harness.replies, hasLength(2));
      expect(harness.controller.loading.value, isTrue);
      harness.replies.last.complete(_rows([_member('peer')]));
      await flight;
      expect(harness.controller.members.single.userID, 'peer');
      expect(harness.controller.failed.value, isFalse);
    });
  }

  test('a permission invalidation cancels a waiting retry', () async {
    await harness.close();
    harness = _Harness(retryDelay: const Duration(milliseconds: 50));
    final flight = harness.refresh();
    harness.replies.single.complete(_rows([]));
    await _drain();
    harness.controller.invalidate();
    await flight;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(harness.replies, hasLength(1));
    expect(harness.controller.loading.value, isFalse);
    expect(harness.controller.failed.value, isFalse);
    expect(harness.controller.members, isEmpty);
  });

  test('a changed session during retry prevents another request', () async {
    await harness.close();
    harness = _Harness(retryDelay: const Duration(milliseconds: 50));
    final flight = harness.refresh();
    harness.replies.single.complete(_rows([]));
    await _drain();
    harness.current = false;
    await flight;
    expect(harness.replies, hasLength(1));
    expect(harness.controller.loading.value, isFalse);
    expect(harness.controller.failed.value, isFalse);
  });

  test('dispose cancels delayed retry and rejects late rows', () async {
    await harness.close();
    harness = _Harness(retryDelay: const Duration(milliseconds: 50));
    final flight = harness.refresh();
    harness.replies.single.complete(_rows([]));
    await _drain();
    harness.controller.dispose();
    await flight;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(harness.replies, hasLength(1));
    expect(harness.controller.members, isEmpty);
    await harness.refresh();
    expect(harness.replies, hasLength(1));
  });

  test('duplicate rows are collapsed and owner/admin precede members',
      () async {
    final flight = harness.refresh();
    harness.replies.single.complete(_rows([
      _member('peer'),
      _member('admin', role: GroupRoleLevel.admin),
      _member('owner', role: GroupRoleLevel.owner),
      _member('peer'),
      {..._member('foreign'), 'groupID': 'other'},
    ]));
    await flight;
    expect(harness.controller.members.map((row) => row.userID), [
      'owner',
      'admin',
      'peer',
    ]);
  });
}
