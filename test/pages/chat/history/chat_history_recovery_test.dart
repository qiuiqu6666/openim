import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_history_recovery.dart';

void main() {
  testWidgets('a retry timer waits for an intervening read to settle',
      (tester) async {
    var loading = false;
    var error = true;
    var retries = 0;
    final recovery = ChatHistoryRecovery(
      isActive: () => true,
      hasError: () => error,
      isLoading: () => loading,
      windowRevision: () => 1,
      retry: () async {
        retries++;
        error = false;
        return true;
      },
    );
    try {
      recovery.request();
      // A manual read starts before the timer and clears the previous error.
      loading = true;
      error = false;
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 0);
      loading = false;
      error = true;
      recovery.loadingSettled();
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 1);
    } finally {
      recovery.close();
    }
  });

  testWidgets('an external recovery during an obsolete retry is retained',
      (tester) async {
    var revision = 1;
    var retries = 0;
    var error = true;
    final oldRead = Completer<bool>();
    final recovery = ChatHistoryRecovery(
      isActive: () => true,
      hasError: () => error,
      isLoading: () => false,
      windowRevision: () => revision,
      retry: () {
        retries++;
        if (retries == 1) return oldRead.future;
        error = false;
        return Future.value(true);
      },
    );
    try {
      recovery.request();
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 1);
      revision++;
      recovery.request(resetAttempts: true);
      oldRead.complete(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 2);
    } finally {
      recovery.close();
    }
  });

  testWidgets('a new failed window replaces an obsolete scheduled retry',
      (tester) async {
    var revision = 1;
    var retries = 0;
    final recovery = ChatHistoryRecovery(
      isActive: () => true,
      hasError: () => retries == 0,
      isLoading: () => false,
      windowRevision: () => revision,
      retry: () async {
        retries++;
        return true;
      },
    );
    try {
      recovery.request();
      revision++;
      recovery.request();
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 1);
    } finally {
      recovery.close();
    }
  });

  testWidgets('internal failures stay bounded until a new external recovery',
      (tester) async {
    var retries = 0;
    final recovery = ChatHistoryRecovery(
      isActive: () => true,
      hasError: () => true,
      isLoading: () => false,
      windowRevision: () => 1,
      retry: () async {
        retries++;
        return false;
      },
    );
    try {
      recovery.request();
      for (final delay in [1, 3, 60]) {
        await tester.pump(Duration(seconds: delay));
      }
      expect(retries, 2);
      recovery.request(resetAttempts: true);
      await tester.pump(const Duration(seconds: 1));
      expect(retries, 3);
      recovery.close();
      await tester.pump(const Duration(seconds: 60));
      expect(retries, 3);
    } finally {
      recovery.close();
    }
  });
}
