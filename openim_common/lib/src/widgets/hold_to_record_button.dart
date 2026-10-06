import 'dart:io';
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:voice_note_kit/voice_note_kit.dart';
import 'package:voice_note_kit/recorder/voice_enums/voice_enums.dart';
import 'chat/chat_composer_palette.dart';
import '../res/chat_voice_tokens.dart';
import 'chat/voice/chat_voice_panel_layout.dart';
import 'chat/voice/chat_voice_panel_view.dart';

class HoldToRecordButton extends StatefulWidget {
  const HoldToRecordButton(
      {super.key,
      required this.onRecorded,
      this.onConvertToText,
      this.expandedPanel = false,
      this.enabled = true});
  final Future<void> Function(String path, int seconds) onRecorded;
  final Future<void> Function(String path, int seconds)? onConvertToText;
  final bool enabled;
  final bool expandedPanel;
  @override
  State<HoldToRecordButton> createState() => _HoldToRecordButtonState();
}

class _HoldToRecordButtonState extends State<HoldToRecordButton>
    with WidgetsBindingObserver {
  bool busy = false;
  bool foreground = true;
  bool _routeActive = true;
  int _cancelGeneration = 0;
  bool _convertToText = false;
  final _recorderController = VoiceRecorderController();
  final _micKey = GlobalKey();
  OverlayEntry? _overlay;
  Timer? _waveTimer;
  int? _pointer;
  Offset? _micAnchor;
  ChatVoiceReleaseZone _zone = ChatVoiceReleaseZone.send;
  final List<double> _levels = [];
  String? _errorText;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorderController.addListener(_recordingChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = ModalRoute.of(context)?.isCurrent ?? true;
    if (!_routeActive) _cancelGesture();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Unmount the recorder when backgrounded, cancelling any active recording.
    if (mounted) {
      if (state != AppLifecycleState.resumed) _cancelGesture();
      setState(() => foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelGeneration++;
    _pointer = null;
    _hideOverlay();
    _recorderController.removeListener(_recordingChanged);
    unawaited(_recorderController.cancel());
    _recorderController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HoldToRecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || oldWidget.expandedPanel != widget.expandedPanel) {
      _cancelGesture();
    }
  }

  void _recordingChanged() {
    if (!mounted || !widget.expandedPanel) return;
    final state = _recorderController.snapshot;
    // Native stop finishes before the parent may open the conversion review.
    // Do not leave this overlay above that existing review while it is awaited.
    if (!state.isStarting && !state.isRecording) {
      _hideOverlay();
    } else {
      _overlay?.markNeedsBuild();
    }
  }

  void _hideOverlay() {
    _waveTimer?.cancel();
    _waveTimer = null;
    final overlay = _overlay;
    _overlay = null;
    overlay?.remove();
    overlay?.dispose();
  }

  void _showOverlay() {
    if (_overlay != null) return;
    final box = _micKey.currentContext?.findRenderObject();
    _micAnchor = box is RenderBox && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : null;
    final entry = OverlayEntry(
        builder: (_) => Positioned.fill(
              child: AbsorbPointer(
                  child: ChatVoiceRecordingOverlay(
                anchorGlobal: _micAnchor,
                zone: _zone,
                levels: List<double>.unmodifiable(_levels),
                seconds: _recorderController.snapshot.seconds,
                preparing: _recorderController.snapshot.isStarting,
                allowConvert: widget.onConvertToText != null,
              )),
            ));
    _overlay = entry;
    Overlay.of(context).insert(entry);
    _waveTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final state = _recorderController.snapshot;
      if (!state.isRecording || state.isStopping) return;
      // Keep a rolling history of actual microphone levels. No synthetic
      // oscillation: silence remains a low, steady waveform.
      _levels.add(state.amplitude);
      if (_levels.length > ChatVoiceTokens.waveformCount) {
        _levels.removeAt(0);
      }
      _overlay?.markNeedsBuild();
    });
  }

  void _startGesture(PointerDownEvent event) {
    final mic = _micKey.currentContext?.findRenderObject();
    if (mic is! RenderBox ||
        !mic.hasSize ||
        !(mic.localToGlobal(Offset.zero) & mic.size).contains(event.position)) {
      return;
    }
    final state = _recorderController.snapshot;
    if (_pointer != null ||
        busy ||
        !foreground ||
        !_routeActive ||
        !widget.enabled ||
        state.isStarting ||
        state.isRecording ||
        state.isStopping) {
      return;
    }
    _pointer = event.pointer;
    _convertToText = false;
    _zone = ChatVoiceReleaseZone.send;
    _levels.clear();
    if (_errorText != null) setState(() => _errorText = null);
    _showOverlay();
    unawaited(_startRecordingGesture(event.pointer));
  }

  Future<void> _startRecordingGesture(int pointer) async {
    await _recorderController.start();
    if (!mounted || _pointer != pointer) return;
    final state = _recorderController.snapshot;
    if (!state.isStarting && !state.isRecording) {
      _pointer = null;
      _hideOverlay();
    }
  }

  ChatVoiceReleaseZone _releaseZone(Offset global) {
    final overlayBox = Overlay.of(context).context.findRenderObject();
    final local =
        overlayBox is RenderBox ? overlayBox.globalToLocal(global) : global;
    final anchor = _micAnchor;
    final localAnchor = anchor != null && overlayBox is RenderBox
        ? overlayBox.globalToLocal(anchor)
        : anchor;
    final media = MediaQuery.of(context);
    final height = ChatVoiceTokens.panelHeight + media.padding.bottom;
    final top = media.size.height - height;
    final layout = ChatVoiceControlsLayout(
      panelSize: Size(media.size.width, height),
      bottomInset: media.padding.bottom,
      anchorCenter: localAnchor == null
          ? null
          : Offset(localAnchor.dx, localAnchor.dy - top),
    );
    final result = layout.hitTest(Offset(local.dx, local.dy - top));
    return result == ChatVoiceReleaseZone.convertText &&
            widget.onConvertToText == null
        ? ChatVoiceReleaseZone.send
        : result;
  }

  void _moveGesture(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    final next = _releaseZone(event.position);
    if (_zone != next) {
      _zone = next;
      _overlay?.markNeedsBuild();
    }
  }

  Future<void> _finishGesture(PointerUpEvent event) async {
    if (_pointer != event.pointer) return;
    _zone = _releaseZone(event.position);
    _pointer = null;
    _convertToText = _zone == ChatVoiceReleaseZone.convertText;
    if (_zone == ChatVoiceReleaseZone.cancel) {
      await _recorderController.cancel();
    } else {
      await _recorderController.stop();
    }
    _hideOverlay();
  }

  void _cancelGesture() {
    _cancelGeneration++;
    _pointer = null;
    _hideOverlay();
    unawaited(_recorderController.cancel());
  }

  void _maxDurationReached() {
    if (!mounted || !widget.expandedPanel) return;
    // The plugin has begun native stop but has not delivered its file yet.
    // Freeze the current intent so a later pointer-up cannot change it.
    final zone = _zone;
    _pointer = null;
    _convertToText = zone == ChatVoiceReleaseZone.convertText &&
        widget.onConvertToText != null;
    if (zone == ChatVoiceReleaseZone.cancel) {
      _hideOverlay();
      // Cancelling the in-flight stop marks the file as discarded before the
      // native result can reach onRecorded.
      unawaited(_recorderController.cancel());
    }
  }

  Widget _expandedRecorder(
          BuildContext context, VoiceRecorderController controller) =>
      RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            () => EagerGestureRecognizer(),
            (_) {},
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _startGesture,
          onPointerMove: _moveGesture,
          onPointerUp: (event) => unawaited(_finishGesture(event)),
          onPointerCancel: (event) {
            if (_pointer == event.pointer) _cancelGesture();
          },
          child: ChatVoiceIdlePanel(
            height: ChatVoiceTokens.panelHeight +
                MediaQuery.paddingOf(context).bottom,
            micKey: _micKey,
            active: controller.snapshot.isRecording ||
                controller.snapshot.isStarting,
            busy: busy,
            errorText: _errorText,
          ),
        ),
      );

  Future<void> recorded(File file) async {
    final generation = _cancelGeneration;
    if (!mounted || busy || !foreground || !_routeActive || !widget.enabled) {
      if (await file.exists()) await file.delete();
      return;
    }
    setState(() => busy = true);
    // Current visibility alone is insufficient: a route or input mode can be
    // changed and restored while duration decoding or copying is still pending.
    bool isCurrentRecording() =>
        mounted &&
        foreground &&
        _routeActive &&
        widget.enabled &&
        generation == _cancelGeneration;
    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(file.path);
      if (!isCurrentRecording()) return;
      if (duration == null || duration.inMilliseconds < 1000) {
        _showRecordingError('录音时间太短，请按住后说话');
        return;
      }
      final directory = Directory('${Config.cachePath}/outgoing_media');
      await directory.create(recursive: true);
      final saved = await file.copy(
          '${directory.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a');
      if (!isCurrentRecording()) {
        await saved.delete();
        return;
      }
      final callback = _convertToText && widget.onConvertToText != null
          ? widget.onConvertToText!
          : widget.onRecorded;
      await callback(
          saved.path, (duration.inMilliseconds / 1000).ceil().clamp(1, 60));
    } catch (_) {
      if (isCurrentRecording()) _showRecordingError(StrRes.voiceCaptureFailed);
    } finally {
      try {
        await player.dispose();
      } finally {
        try {
          if (await file.exists()) await file.delete();
        } finally {
          if (mounted) setState(() => busy = false);
        }
      }
    }
  }

  void _showRecordingError(String message) {
    if (!mounted || !foreground || !_routeActive || !widget.enabled) return;
    setState(() => _errorText = message);
    IMViews.showToast(message);
  }

  @override
  Widget build(BuildContext context) {
    if (!foreground || !widget.enabled) return const SizedBox.shrink();
    final recorder = VoiceRecorderWidget(
      controller: _recorderController,
      builder: widget.expandedPanel ? _expandedRecorder : null,
      style: VoiceUIStyle.compact,
      idleText: busy
          ? (_convertToText ? 'voiceToTextLoading'.tr : '正在发送…')
          : (_convertToText ? 'voiceRecordConvert'.tr : '按住说话'),
      borderRadius: 8,
      onRecorded: recorded,
      onError: (error) => _showRecordingError(
          error == '请允许使用麦克风' ? error : StrRes.voiceCaptureFailed),
      actionWhenCancel: () {},
      maxRecordDuration: const Duration(seconds: 60),
      onMaxDurationReached: _maxDurationReached,
      permissionNotGrantedMessage: '请允许使用麦克风',
      recordCancelledMessage: '已取消录音',
      cancelDoneText: '已取消',
      dragToLeftText:
          _convertToText ? 'voiceRecordConvertHint'.tr : '左滑取消，松开发送',
      iconSize: 22,
      timerFontSize: 12,
      backgroundColor: Styles.c_0089FF,
      iconColor: Styles.c_0089FF,
      containerColor: chatComposerInputFill(context),
      borderColor: Colors.transparent,
      cancelHintColor: Styles.c_FF381F,
      idleWavesColor: Styles.c_8E9AB0,
      recordingWavesColor: Styles.c_0089FF,
      timerTextStyle: TextStyle(color: Styles.c_0C1C33, fontSize: 12),
      dragToLeftTextStyle: TextStyle(color: Styles.c_0C1C33, fontSize: 14),
    );
    return IgnorePointer(
      ignoring: busy,
      // Keep the recorder at the same element position when presentation
      // changes, so one controller remains attached to one native recorder.
      child: Row(children: [
        Expanded(child: recorder),
        if (!widget.expandedPanel && widget.onConvertToText != null)
          IconButton(
            tooltip: _convertToText
                ? 'voiceSendOriginal'.tr
                : 'voiceRecordConvert'.tr,
            isSelected: _convertToText,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            selectedIcon: Icon(Icons.text_fields_rounded,
                color: Theme.of(context).colorScheme.primary),
            icon: const Icon(Icons.text_fields_rounded),
            onPressed: () => setState(() => _convertToText = !_convertToText),
          ),
      ]),
    );
  }
}
