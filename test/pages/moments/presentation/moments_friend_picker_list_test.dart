import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/directory/contact_directory_indexer.dart';
import 'package:openim/pages/moments/presentation/moments_friend_picker_list.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

const _alice = MomentUser(userId: 'alice', nickname: 'Alice');
const _bob = MomentUser(userId: 'bob', nickname: 'Bob');
const _carol = MomentUser(userId: 'carol', nickname: 'Carol');

class _HeldIndexWorker {
  final requests = <List<ContactNameIndex>>[];
  final pending = <Completer<List<ContactNameIndex>>>[];

  Future<List<ContactNameIndex>> call(List<ContactNameIndex> names) {
    requests.add(names);
    if (requests.length == 1) {
      return Future.value(buildContactNameIndex(names));
    }
    final result = Completer<List<ContactNameIndex>>();
    pending.add(result);
    return result.future;
  }

  void complete(int pendingIndex) => pending[pendingIndex]
      .complete(buildContactNameIndex(requests[pendingIndex + 1]));
}

Widget _host(List<MomentUser> friends, _HeldIndexWorker worker,
        ValueChanged<MomentUser> onToggle) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) {
        Styles.isDark = false;
        return MaterialApp(
            home: Scaffold(
                body: MomentsFriendPickerList(
          key: const ValueKey('friend-picker'),
          friends: friends,
          selected: const {},
          onToggle: onToggle,
          indexWorker: worker.call,
        )));
      },
    );

void main() {
  testWidgets('replacing friends immediately removes old names and callbacks',
      (tester) async {
    final worker = _HeldIndexWorker();
    final selected = <String>[];
    void toggle(MomentUser friend) => selected.add(friend.userId);
    await tester.pumpWidget(_host([_alice], worker, toggle));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);

    await tester.pumpWidget(_host([_bob], worker, toggle));
    expect(worker.pending.single.isCompleted, isFalse);
    expect(find.text('Alice'), findsNothing);
    expect(find.byKey(const ValueKey('moments_privacy_friend_alice')),
        findsNothing);
    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('moments_privacy_friend_bob')));
    expect(selected, ['bob']);

    worker.complete(0);
    await tester.pump();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'clearing friends removes the previous indexed account in one frame',
      (tester) async {
    final worker = _HeldIndexWorker();
    final selected = <String>[];
    void toggle(MomentUser friend) => selected.add(friend.userId);
    await tester.pumpWidget(_host([_alice], worker, toggle));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);

    await tester.pumpWidget(_host([], worker, toggle));
    expect(worker.pending.single.isCompleted, isFalse);
    expect(find.text('Alice'), findsNothing);
    expect(find.byKey(const ValueKey('moments_privacy_friend_alice')),
        findsNothing);
    expect(selected, isEmpty);

    worker.complete(0);
    await tester.pump();
    expect(find.text('Alice'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an older completed index cannot restore a superseded friend list',
      (tester) async {
    final worker = _HeldIndexWorker();
    void toggle(MomentUser _) {}
    await tester.pumpWidget(_host([_alice], worker, toggle));
    await tester.pump();
    await tester.pumpWidget(_host([_bob], worker, toggle));
    await tester.pumpWidget(_host([_carol], worker, toggle));

    worker.complete(0);
    await tester.pump();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Carol'), findsOneWidget);
    worker.complete(1);
    await tester.pump();
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Carol'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mutating the input list cannot retain a previous display snapshot',
      (tester) async {
    final worker = _HeldIndexWorker();
    final friends = <MomentUser>[_alice];
    void toggle(MomentUser _) {}
    await tester.pumpWidget(_host(friends, worker, toggle));
    await tester.pump();
    friends[0] = _bob;
    await tester.pumpWidget(_host(friends, worker, toggle));
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
    worker.complete(0);
    await tester.pump();
    expect(find.text('Alice'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
