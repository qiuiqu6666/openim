import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:focus_detector_v2/focus_detector_v2.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:openim_common/openim_common.dart';

class ChatFileMessageView extends StatefulWidget {
  const ChatFileMessageView({super.key, required this.message});
  final Message message;
  @override
  State<ChatFileMessageView> createState() => _ChatFileMessageViewState();
}

class _ChatFileMessageViewState extends State<ChatFileMessageView> {
  bool _busy = false;
  bool _failed = false;
  bool _downloaded = false;
  double? _progress;

  Future<void> _open() async {
    if (_busy) return;
    setState(() { _busy = true; _failed = false; _progress = null; });
    try {
      final element = widget.message.fileElem!;
      File? file;
      final path = element.filePath;
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        file = File(path);
      } else {
        final url = element.sourceUrl;
        if (url == null || url.isEmpty) throw StateError('Missing file URL');
        await for (final event in DefaultCacheManager().getFileStream(url, withProgress: true)) {
          if (!mounted) return;
          if (event is DownloadProgress) setState(() => _progress = event.progress);
          if (event is FileInfo) file = event.file;
        }
      }
      if (!mounted) return;
      if (file == null) throw StateError('Missing downloaded file');
      final name = element.fileName ?? '';
      // Cache URLs may have no extension; retain the platform file association.
      final extension = RegExp(r'\.([a-zA-Z0-9]{1,12})$').firstMatch(name)?.group(0);
      if (extension != null && !file.path.endsWith(extension)) {
        file = await file.copy('${file.path}$extension');
      }
      if (!mounted) return;
      setState(() => _downloaded = true);
      final result = await OpenFilex.open(file.path,
          type: extension == null ? null : IMUtils.getMediaType(name));
      if (result.type != ResultType.done) throw StateError(result.message);
      if (mounted) setState(() => _downloaded = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.message.fileElem!;
    final bytes = file.fileSize ?? 0;
    final size = bytes < 1024 ? '$bytes B' : bytes < 1048576
        ? '${(bytes / 1024).toStringAsFixed(1)} KB'
        : '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(width: 220, child: Row(children: [
        Icon(Icons.insert_drive_file_outlined, size: 32, color: Styles.c_0089FF),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(file.fileName ?? 'attachmentFile'.tr, maxLines: 2,
              overflow: TextOverflow.ellipsis, style: Styles.ts_0C1C33_17sp),
          Text(size, style: Styles.ts_8E9AB0_12sp),
          Text(_busy ? (_progress == null ? 'attachmentLoading'.tr
              : '${(_progress! * 100).round()}%') : _failed ? 'attachmentRetry'.tr
              : _downloaded ? 'attachmentOpen'.tr : 'attachmentDownload'.tr,
              style: Styles.ts_8E9AB0_12sp),
        ])),
      ])),
    );
  }
}

class ChatVoiceMessageView extends StatefulWidget {
  const ChatVoiceMessageView({super.key, required this.message, required this.isOutgoing});
  final Message message;
  final bool isOutgoing;
  @override
  State<ChatVoiceMessageView> createState() => _ChatVoiceMessageViewState();
}

class _ChatVoiceMessageViewState extends State<ChatVoiceMessageView>
    with WidgetsBindingObserver {
  static _ChatVoiceMessageViewState? _active;
  static int _generation = 0;
  AudioPlayer? _player;
  bool _loading = false;
  bool _playing = false;
  bool _failed = false;
  bool _heard = false;
  bool _loaded = false;
  Future<void>? _loadingSource;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }

  void _stop() {
    if (_active == this) { _active = null; _generation++; }
    unawaited(_player?.pause());
    if (mounted) setState(() { _playing = false; _loading = false; });
  }

  Future<void> _toggle() async {
    if (_playing || _loading) { _stop(); return; }
    _active?._stop();
    _active = this;
    final generation = ++_generation;
    setState(() { _loading = true; _failed = false; });
    try {
      final player = _player ??= AudioPlayer();
      if (!_loaded) await (_loadingSource ??= _loadSource(player));
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      if (!mounted || generation != _generation) return;
      setState(() { _loading = false; _playing = true; _heard = true; });
      await player.play();
      if (mounted && generation == _generation) _stop();
    } catch (_) {
      if (mounted && generation == _generation) {
        _stop();
        setState(() => _failed = true);
      }
    }
  }

  Future<void> _loadSource(AudioPlayer player) async {
    try {
      final sound = widget.message.soundElem!;
      final path = sound.soundPath;
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        await player.setFilePath(path);
      } else {
        final url = sound.sourceUrl;
        if (url == null || url.isEmpty) throw StateError('Missing audio URL');
        await player.setUrl(url);
      }
      _loaded = true;
    } finally {
      _loadingSource = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_active == this) { _active = null; _generation++; }
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.message.soundElem?.duration ?? 0;
    return FocusDetector(
      onFocusLost: _stop,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Semantics(button: true,
          label: _playing ? 'attachmentPause'.tr : 'attachmentPlay'.tr,
          child: SizedBox(width: (96 + duration * 2).clamp(96, 210).toDouble(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_loading ? Icons.hourglass_top : _playing ? Icons.pause
                  : Icons.play_arrow, color: Styles.c_0C1C33),
              const SizedBox(width: 8),
              Flexible(child: Text(_failed ? 'attachmentRetry'.tr : '$duration″',
                  style: Styles.ts_0C1C33_17sp)),
              if (!widget.isOutgoing && !_heard && widget.message.isRead != true) ...[
                const SizedBox(width: 6),
                Icon(Icons.circle, size: 6, color: Styles.c_0089FF),
              ],
            ])),
        ),
      ),
    );
  }
}
