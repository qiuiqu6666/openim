// Reference export task workflow; no download credential is placed in a URL.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../../data/mark_six_repository.dart';
import '../models/agent_date_range.dart';

class AgentHistoryExport extends ChangeNotifier with WidgetsBindingObserver {
  AgentHistoryExport(this.repository) {
    WidgetsBinding.instance.addObserver(this);
  }
  final MarkSixRepository repository;
  bool busy = false;
  String? error;
  bool _disposed = false;
  int _generation = 0;
  bool _foreground = true;
  bool _current(int generation) =>
      !_disposed &&
      _foreground &&
      generation == _generation &&
      repository.privateCurrent;
  Future<bool> save(AgentRebateDateRange range) async {
    if (busy || _disposed || !_foreground || !repository.privateCurrent) {
      return false;
    }
    final generation = ++_generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      var task = MarkSixRepository.payload(
          await repository.post('/me/agent/rebate/history/export', body: {
        'startDate': range.startApiValue,
        'endDate': range.endApiValue,
        'fileType': 'CSV',
        'includeDetail': true
      }));
      if (!_current(generation)) return false;
      final taskNo = '${task['taskNo'] ?? ''}'.trim();
      if (taskNo.isEmpty) throw const FormatException('导出任务编号缺失');
      final path =
          '/me/agent/rebate/history/export/${Uri.encodeComponent(taskNo)}';
      for (var attempt = 0;
          ['PENDING', 'PROCESSING', 'RUNNING']
                  .contains('${task['status']}'.toUpperCase()) &&
              attempt < 40;
          attempt++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!_current(generation)) return false;
        task =
            MarkSixRepository.payload(await repository.read(path, force: true));
        if (!_current(generation)) return false;
      }
      if (!['COMPLETED', 'SUCCESS', 'DONE']
          .contains('${task['status']}'.toUpperCase())) {
        throw StateError('${task['errorMessage'] ?? '导出尚未完成，请稍后重试'}');
      }
      final bytes = await repository.context.api
          .getBytes('$path/download', headers: repository.headers);
      if (!_current(generation)) return false;
      if (bytes.isEmpty) throw const FormatException('导出文件为空');
      final rawName =
          '${task['fileName'] ?? '代理反水历史_${range.startApiValue}_${range.endApiValue}.csv'}';
      final name = rawName.replaceAll(RegExp(r'[/\\\x00-\x1F]'), '_');
      final extension = name.split('.').last.toLowerCase();
      final saved = await FilePicker.platform.saveFile(
          dialogTitle: '保存反水历史',
          fileName: name,
          type: FileType.custom,
          allowedExtensions: [extension],
          bytes: Uint8List.fromList(bytes));
      if (!_current(generation)) return false;
      if (!kIsWeb && saved != null) await OpenFilex.open(saved);
      return kIsWeb || saved != null;
    } catch (failure) {
      if (_current(generation)) error = failure.toString();
      return false;
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && !_disposed) {
      _generation++;
      busy = false;
      if (repository.privateCurrent) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
