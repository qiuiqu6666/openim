import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// The real SDK renderer is part of the production participant boundary.
// ignore: depend_on_referenced_packages
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
// ignore: depend_on_referenced_packages
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/pages/single/widgets/participant.dart';
import 'package:openim_live/src/widgets/call_compact_surface.dart';
import 'package:openim_live/src/widgets/live_button.dart';

import 'support/video_preview_fixture.dart';

const _previewKey = ValueKey('call-video-preview');

Finder get _preview => find.byKey(_previewKey);

void main() {
  installVideoPreviewNativeMocks();
  testWidgets('tapping the actual full-screen preview swaps both SDK tracks',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state = await mountVideoPreview(tester, probe: probe);
    try {
      final originalSession = state.session;
      final local = find.byType(LocalParticipantWidget);
      final remote = find.byType(RemoteParticipantWidget);
      expect(local, findsOneWidget);
      expect(remote, findsOneWidget);
      expect(tester.getSize(local), const Size(96, 144));
      expect(tester.getSize(remote), const Size(375, 812));

      await tester.tapAt(tester.getCenter(local));
      await pumpVideoPreviewFrames(tester);

      expect(tester.getSize(local), const Size(375, 812));
      expect(tester.getSize(remote), const Size(96, 144));
      expectVideoSessionUnchanged(state, probe, originalSession,
          connected: true);
      expect(
          videoPreviewRtcMethods
              .where((method) => method == 'getUserMedia')
              .length,
          1);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  testWidgets('native RTCVideoView fills the bounded preview with cover fit',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state = await mountVideoPreview(tester, probe: probe);
    try {
      for (final type in [LocalParticipantWidget, RemoteParticipantWidget]) {
        final participant = find.byType(type);
        final renderer = find.descendant(
            of: participant, matching: find.byType(VideoTrackRenderer));
        final view = find.descendant(
            of: renderer, matching: find.byType(rtc.RTCVideoView));
        expect(renderer, findsOneWidget);
        expect(view, findsOneWidget);
        expect(tester.widget<VideoTrackRenderer>(renderer).fit,
            VideoViewFit.cover);
        expect(tester.widget<rtc.RTCVideoView>(view).objectFit,
            rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
        expect(tester.getRect(view), tester.getRect(participant));
      }
      // This test covers Flutter bounds and fit. A native texture mock has no
      // camera pixels and cannot prove that a source frame has no baked bars.
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  testWidgets('waiting local camera can become full screen from preview tap',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state = await mountVideoPreview(tester,
        probe: probe, connected: false, withRemote: false);
    try {
      final originalSession = state.session;
      final local = find.byType(LocalParticipantWidget);
      expect(local, findsOneWidget);
      expect(tester.getSize(local), const Size(96, 144));

      // Deliberately locates the actual old SDK widget, not a new production
      // key. This assertion reproduces the old remote == null tap guard.
      await tester.tapAt(tester.getCenter(local));
      await pumpVideoPreviewFrames(tester);

      expect(tester.getSize(local), const Size(375, 812));
      expectVideoSessionUnchanged(state, probe, originalSession,
          connected: false);
      expect(_preview, findsOneWidget);
      final fallback =
          find.descendant(of: _preview, matching: find.byType(AvatarView));
      expect(fallback, findsOneWidget);
      expect(tester.getSize(_preview), const Size(96, 144));
      await tester.tapAt(tester.getCenter(fallback));
      await pumpVideoPreviewFrames(tester);
      expect(tester.getSize(local), const Size(96, 144));
      expectVideoSessionUnchanged(state, probe, originalSession,
          connected: false);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  testWidgets('preview edge taps switch repeatedly without starting new media',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state = await mountVideoPreview(tester, probe: probe);
    try {
      final originalSession = state.session;
      final local = find.byType(LocalParticipantWidget);
      for (var i = 0; i < 6; i++) {
        final rect = tester.getRect(_preview);
        // Near the rounded clip: the preview must own every visible hit.
        await tester.tapAt(rect.topLeft + const Offset(10, 10));
        await pumpVideoPreviewFrames(tester);
        expect(tester.getSize(local),
            i.isEven ? const Size(375, 812) : const Size(96, 144));
        expectVideoSessionUnchanged(state, probe, originalSession,
            connected: true);
      }
      expect(
          videoPreviewRtcMethods
              .where((method) => method == 'getUserMedia')
              .length,
          1);
      expect(videoPreviewRtcMethods.where((method) => method == 'trackDispose'),
          isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  testWidgets('muted cameras still switch their bounded placeholders',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state = await mountVideoPreview(tester, probe: probe);
    try {
      final originalSession = state.session;
      state.setMuted(true);
      await pumpVideoPreviewFrames(tester);
      expect(find.byType(VideoTrackRenderer), findsNothing);
      expect(tester.getSize(find.byType(LocalParticipantWidget)),
          const Size(96, 144));
      await tester.tapAt(tester.getCenter(_preview));
      await pumpVideoPreviewFrames(tester);
      expect(tester.getSize(find.byType(LocalParticipantWidget)),
          const Size(375, 812));
      expect(tester.getSize(find.byType(RemoteParticipantWidget)),
          const Size(96, 144));
      state.setMuted(false);
      await pumpVideoPreviewFrames(tester);
      expect(find.byType(VideoTrackRenderer), findsNWidgets(2));
      expectVideoSessionUnchanged(state, probe, originalSession,
          connected: true);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  testWidgets('missing remote camera retains an avatar preview to switch back',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state =
        await mountVideoPreview(tester, probe: probe, withRemote: false);
    try {
      final originalSession = state.session;
      await tester.tapAt(tester.getCenter(_preview));
      await pumpVideoPreviewFrames(tester);
      expect(tester.getSize(find.byType(LocalParticipantWidget)),
          const Size(375, 812));
      expect(find.descendant(of: _preview, matching: find.byType(AvatarView)),
          findsOneWidget);
      await tester.tapAt(tester.getCenter(_preview));
      await pumpVideoPreviewFrames(tester);
      expect(tester.getSize(find.byType(LocalParticipantWidget)),
          const Size(96, 144));
      expectVideoSessionUnchanged(state, probe, originalSession,
          connected: true);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  testWidgets(
      'preview hides after both cameras are removed without ending call',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state = await mountVideoPreview(tester, probe: probe);
    try {
      final originalSession = state.session;
      state.clearCameras();
      await pumpVideoPreviewFrames(tester);
      expect(_preview, findsNothing);
      expect(find.byType(LocalParticipantWidget), findsNothing);
      expect(find.byType(RemoteParticipantWidget), findsNothing);
      expect(find.byType(VideoTrackRenderer), findsNothing);
      expect(state.session, same(originalSession));
      expect(state.session.active, isTrue);
      expect(state.session.connected, isTrue);
      expect(probe.releases, 0);
      expect(probe.hangups, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  testWidgets('microphone and speaker controls do not exchange the video views',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state = await mountVideoPreview(tester, probe: probe);
    try {
      final originalSession = state.session;
      final localRect = tester.getRect(find.byType(LocalParticipantWidget));
      for (final label in [StrRes.microphone, StrRes.speaker]) {
        final button = find.byWidgetPredicate(
            (widget) => widget is LiveButton && widget.text == label);
        expect(button, findsOneWidget);
        await tester.tap(button);
        await pumpVideoPreviewFrames(tester);
        expect(tester.getRect(find.byType(LocalParticipantWidget)), localRect);
        expectVideoSessionUnchanged(state, probe, originalSession,
            connected: true);
      }
      expect(state.enabledMicrophone, isFalse);
      expect(state.enabledSpeaker, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  testWidgets('minimizing and restoring preserves the selected large camera',
      (tester) async {
    final probe = VideoPreviewProbe();
    final state = await mountVideoPreview(tester, probe: probe);
    try {
      final originalSession = state.session;
      await tester.tapAt(tester.getCenter(_preview));
      await pumpVideoPreviewFrames(tester);
      expect(tester.getSize(find.byType(LocalParticipantWidget)),
          const Size(375, 812));
      await tester.tap(find.byTooltip('最小化'));
      await pumpVideoPreviewFrames(tester);
      expect(state.minimize, isTrue);
      expect(find.byType(CallCompactSurface), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.byType(CallCompactSurface)));
      await pumpVideoPreviewFrames(tester);
      expect(state.minimize, isFalse);
      expect(tester.getSize(find.byType(LocalParticipantWidget)),
          const Size(375, 812));
      expect(tester.getSize(find.byType(RemoteParticipantWidget)),
          const Size(96, 144));
      expectVideoSessionUnchanged(state, probe, originalSession,
          connected: true);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVideoPreview(tester, state);
    }
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
        '${brightness.name} narrow screen preview fills cover bounds after native size changes',
        (tester) async {
      final probe = VideoPreviewProbe();
      final state = await mountVideoPreview(tester,
          probe: probe, brightness: brightness, size: const Size(320, 568));
      try {
        final rect = tester.getRect(_preview);
        expect(rect.size, const Size(96, 144));
        expect(rect.top, greaterThanOrEqualTo(24));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.bottom, lessThanOrEqualTo(568 - 24));
        for (final dimensions in [
          const Size(640, 360),
          const Size(360, 640),
          const Size(640, 640)
        ]) {
          for (final view in tester
              .widgetList<rtc.RTCVideoView>(find.byType(rtc.RTCVideoView))) {
            // A real SDK renderer receives native aspect-ratio metadata.
            // This does not fabricate or inspect camera source pixels.
            view.videoRenderer.eventListener({
              'event': 'didTextureChangeVideoSize',
              'width': dimensions.width,
              'height': dimensions.height,
            });
          }
          await pumpVideoPreviewFrames(tester);
          final native = find.descendant(
              of: _preview, matching: find.byType(rtc.RTCVideoView));
          expect(native, findsOneWidget);
          expect(tester.getRect(native), rect);
          expect(tester.widget<rtc.RTCVideoView>(native).objectFit,
              rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
          expect(tester.takeException(), isNull);
        }
        // Windows does not enter LiveKit's dart:io mobile focus/zoom branch.
        // The production IgnorePointer must exclude that entire SDK subtree,
        // rather than relying on Windows' successful native-view tap alone.
        final ignoredVideo = find.descendant(
            of: _preview,
            matching: find.byWidgetPredicate(
                (widget) => widget is IgnorePointer && widget.ignoring));
        expect(ignoredVideo, findsOneWidget);
        expect(
            find.descendant(
                of: ignoredVideo, matching: find.byType(VideoTrackRenderer)),
            findsOneWidget);
        await tester.tapAt(rect.center);
        await pumpVideoPreviewFrames(tester);
        expect(tester.getSize(find.byType(LocalParticipantWidget)),
            const Size(320, 568));
        expect(tester.takeException(), isNull);
      } finally {
        await disposeVideoPreview(tester, state);
      }
    });
  }
}
