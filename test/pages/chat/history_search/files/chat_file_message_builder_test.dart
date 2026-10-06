import 'dart:async';
import 'dart:io';

// FileInfo exposes package:file objects; use its in-memory implementation to
// exercise cache and extension-copy behavior without touching real files.
// ignore: depend_on_referenced_packages
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';
import 'package:openim/pages/chat/history_search/files/chat_history_file_tile.dart';
import 'package:openim_common/openim_common.dart';

class _Cache extends Fake implements BaseCacheManager {
  _Cache(this.stream);
  final Stream<FileResponse> Function() stream;
  int calls = 0;

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    expect(url, 'https://test.invalid/attachment');
    expect(withProgress, isTrue);
    calls++;
    return stream();
  }
}

class _Probe {
  bool downloaded = false, busy = false, failed = false;
  double? progress;
  late VoidCallback onOpen;
  int builds = 0;

  Widget build(BuildContext context,
      {required bool downloaded,
      required bool busy,
      required bool failed,
      required double? progress,
      required VoidCallback onOpen}) {
    this.downloaded = downloaded;
    this.busy = busy;
    this.failed = failed;
    this.progress = progress;
    this.onOpen = onOpen;
    builds++;
    return TextButton(onPressed: onOpen, child: const Text('open-file'));
  }
}

Message _message({String id = 'file', String? path, bool private = false}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.file,
      'sendID': 'sender',
      'senderNickname': 'Should not be displayed',
      'sendTime': DateTime(2026, 10, 5, 12, 30).millisecondsSinceEpoch,
      'fileElem': {
        'fileName': 'report.pdf',
        'filePath': path,
        'fileSize': 1024,
        'sourceUrl': 'https://test.invalid/attachment',
      },
      if (private)
        'attachedInfoElem': {
          'isPrivateChat': true,
          'hasReadTime': DateTime.now().millisecondsSinceEpoch,
          'burnDuration': 3600,
        },
    });

Future<void> _mount(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: SizedBox(width: 320, child: child)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.token = 'session-a';
  });

  testWidgets('builder opens an existing local attachment without downloading',
      (tester) async {
    final fs = MemoryFileSystem();
    fs.file('/report.pdf').writeAsStringSync('file');
    final probe = _Probe();
    final cache = _Cache(() => throw StateError('Unexpected download'));
    final opened = <String>[];
    await IOOverrides.runZoned(() async {
      await _mount(
          tester,
          ChatFileMessageView(
              message: _message(path: '/report.pdf'),
              cacheManager: cache,
              builder: probe.build,
              openFile: (path, {type}) async {
                opened.add(path);
                // Existing MIME mapping leaves PDF association to its suffix.
                expect(type, isNull);
                return OpenResult();
              }));
      expect(probe.downloaded, isTrue);
      await tester.tap(find.text('open-file'));
      await tester.pumpAndSettle();
      expect(opened, ['/report.pdf']);
      expect(cache.calls, 0);
      expect(probe.failed, isFalse);
      expect(probe.busy, isFalse);
    }, createFile: fs.file);
  });

  testWidgets(
      'download progress, extension copy and cached reopening are shared',
      (tester) async {
    final fs = MemoryFileSystem();
    final file = fs.file('/download')..writeAsStringSync('file');
    final events = StreamController<FileResponse>();
    final cache = _Cache(() => events.stream);
    final opened = <String>[];
    final probe = _Probe();
    await IOOverrides.runZoned(() async {
      await _mount(
          tester,
          ChatFileMessageView(
            message: _message(),
            cacheManager: cache,
            builder: probe.build,
            openFile: (path, {type}) async {
              opened.add(path);
              return OpenResult();
            },
          ));
      probe.onOpen();
      await tester.pump();
      expect(probe.busy, isTrue);
      probe.onOpen();
      expect(cache.calls, 1);
      events.add(
          const DownloadProgress('https://test.invalid/attachment', 100, 40));
      await tester.pumpAndSettle();
      expect(probe.progress, .4);
      events.add(FileInfo(
          file,
          FileSource.Online,
          DateTime.now().add(const Duration(days: 1)),
          'https://test.invalid/attachment'));
      await events.close();
      await tester.pumpAndSettle();
      expect(opened, ['/download.pdf']);
      expect(fs.file('/download.pdf').readAsStringSync(), 'file');
      expect(probe.downloaded, isTrue);
      expect(probe.failed, isFalse);
      expect(probe.busy, isFalse);
      probe.onOpen();
      await tester.pumpAndSettle();
      expect(opened, ['/download.pdf', '/download.pdf']);
      expect(cache.calls, 1);
    }, createFile: fs.file);
  });

  testWidgets('failed download is retryable and native open failure is exposed',
      (tester) async {
    final fs = MemoryFileSystem();
    final file = fs.file('/download.pdf')..writeAsStringSync('file');
    var downloads = 0, opens = 0;
    final cache = _Cache(() => ++downloads == 1
        ? Stream.error(StateError('offline'))
        : Stream.value(FileInfo(file, FileSource.Cache, DateTime(2099),
            'https://test.invalid/attachment')));
    final probe = _Probe();
    await IOOverrides.runZoned(() async {
      await _mount(
          tester,
          ChatFileMessageView(
            message: _message(),
            cacheManager: cache,
            builder: probe.build,
            openFile: (path, {type}) async => ++opens == 1
                ? OpenResult(type: ResultType.noAppToOpen)
                : OpenResult(),
          ));
      probe.onOpen();
      await tester.pumpAndSettle();
      expect(probe.failed, isTrue);
      expect(opens, 0);
      probe.onOpen();
      await tester.pumpAndSettle();
      expect(probe.failed, isTrue);
      expect(probe.downloaded, isTrue);
      expect(opens, 1);
      probe.onOpen();
      await tester.pumpAndSettle();
      expect(probe.failed, isFalse);
      expect(opens, 2);
      expect(cache.calls, 2);
    }, createFile: fs.file);
  });

  for (final guard in ['dispose', 'account', 'token', 'expiry', 'message']) {
    testWidgets('$guard change during download prevents stale opening',
        (tester) async {
      final fs = MemoryFileSystem();
      final file = fs.file('/download.pdf')..writeAsStringSync('file');
      final events = StreamController<FileResponse>();
      final cache = _Cache(() => events.stream);
      final probe = _Probe();
      var opens = 0;
      final message = _message(private: guard == 'expiry');
      Widget view(Message message) => ChatFileMessageView(
          key: const ValueKey('same-file-widget'),
          message: message,
          cacheManager: cache,
          builder: probe.build,
          openFile: (path, {type}) async {
            opens++;
            return OpenResult();
          });
      await IOOverrides.runZoned(() async {
        await _mount(tester, view(message));
        probe.onOpen();
        await tester.pump();
        switch (guard) {
          case 'dispose':
            await tester.pumpWidget(const SizedBox.shrink());
          case 'account':
            OpenIM.iMManager.userID = 'another-account';
          case 'token':
            OpenIM.iMManager.token = 'session-b';
          case 'expiry':
            message.attachedInfoElem!.hasReadTime =
                DateTime(2020).millisecondsSinceEpoch;
          case 'message':
            await _mount(tester, view(_message(id: 'new-file')));
        }
        events.add(FileInfo(file, FileSource.Online, DateTime(2099),
            'https://test.invalid/attachment'));
        await events.close();
        await tester.pumpAndSettle();
        expect(opens, 0);
        expect(tester.takeException(), isNull);
      }, createFile: fs.file);
    });
  }

  testWidgets('private history file uses original-message flow and expires',
      (tester) async {
    var opened = 0;
    final message = _message(private: true);
    await _mount(tester,
        ChatHistoryFileTile(message: message, onPrivateTap: () => opened++));
    expect(find.byType(ChatFileMessageView), findsNothing);
    await tester.tap(find.text('report.pdf'));
    expect(opened, 1);
    message.attachedInfoElem!.hasReadTime =
        DateTime(2020).millisecondsSinceEpoch;
    await tester.tap(find.text('report.pdf'));
    expect(opened, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('report.pdf'), findsNothing);
    expect(find.text('sdkExpired'), findsOneWidget);
    expect(find.byType(ChatFileMessageView), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('expired file never mounts a downloader', (tester) async {
    final message = _message(private: true)
      ..attachedInfoElem!.hasReadTime = DateTime(2020).millisecondsSinceEpoch;
    await _mount(
        tester,
        ChatHistoryFileTile(
            message: message, onPrivateTap: () => fail('Expired file opened')));
    expect(find.byType(ChatFileMessageView), findsNothing);
    expect(find.text('report.pdf'), findsNothing);
    expect(find.text('sdkExpired'), findsOneWidget);
  });

  testWidgets('page session guard blocks a lazily created public file row',
      (tester) async {
    // This row is created only after the page's original account has left.
    OpenIM.iMManager.userID = 'different-account';
    await _mount(
        tester,
        ChatHistoryFileTile(
          message: _message(),
          canOpen: () => false,
          onPrivateTap: () => fail('Not a private file'),
        ));
    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('attachmentRetry'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('file history row is compact and neutral in $brightness',
        (tester) async {
      var privateOpens = 0;
      await _mount(
          tester,
          ChatHistoryFileTile(
              message: _message(private: true),
              canOpen: () => false,
              onPrivateTap: () => privateOpens++),
          brightness: brightness);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.textContaining('[文件]'), findsNothing);
      expect(find.text('Should not be displayed'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      final filename = tester.widget<Text>(find.text('report.pdf'));
      expect(filename.maxLines, 2);
      expect(filename.style?.fontSize, 16);
      await tester.tap(find.text('report.pdf'));
      expect(privateOpens, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
