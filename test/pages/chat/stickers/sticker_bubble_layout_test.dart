import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/stickers/sticker_bubble_layout.dart';

void _expectSize(Size actual, Size expected) {
  expect(actual.width, closeTo(expected.width, 0.001));
  expect(actual.height, closeTo(expected.height, 0.001));
}

void main() {
  // These fixtures follow reference-99chat's current
  // resolveStickerMessageSize main-chat path, rather than its legacy .82 helper.
  group('99chat main sticker layout contract', () {
    test('wide, square, and unknown stickers match the reference phone cases',
        () {
      const screen = Size(390, 800);
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(416, 304),
              screenSize: screen, availableWidth: 280),
          const Size(144, 144 * 304 / 416));
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(512, 512),
              screenSize: screen, availableWidth: 280),
          const Size.square(144));
      _expectSize(
          StickerBubbleLayout.placeholderSize(
              screenSize: screen, availableWidth: 280),
          const Size.square(144));
    });

    test('small source images fill the same proportional frame', () {
      _expectSize(StickerBubbleLayout.imageSize(const Size(40, 20)),
          const Size(141.75, 70.875));
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(40, 20),
              availableWidth: 375),
          const Size(144, 72));
    });

    test('phone tiers follow width and height boundaries', () {
      const fixtures = <(Size, Size)>[
        (Size(359, 900), Size(132, 66)),
        (Size(360, 699), Size(132, 66)),
        (Size(360, 700), Size(144, 72)),
        (Size(390, 839), Size(144, 72)),
        (Size(390, 840), Size(156, 78)),
      ];
      for (final entry in fixtures) {
        _expectSize(
            StickerBubbleLayout.imageSize(const Size(320, 160),
                screenSize: entry.$1, availableWidth: 400),
            entry.$2);
      }
    });

    test('desktop caps and column factors match the reference', () {
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(512, 512),
              screenSize: const Size(1200, 900),
              availableWidth: 200,
              isDesktop: true),
          const Size.square(68));
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(320, 160),
              screenSize: const Size(1200, 900),
              availableWidth: 1000,
              isDesktop: true),
          const Size(260, 130));
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(320, 160),
              screenSize: const Size(599, 900), availableWidth: 500),
          const Size(156, 78));
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(320, 160),
              screenSize: const Size(600, 900), availableWidth: 500),
          const Size(170, 85));
    });

    test('unbounded rows use the phone or desktop fallback row width', () {
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(320, 160),
              screenSize: const Size(390, 800)),
          const Size(144, 72));
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(320, 160),
              screenSize: const Size(500, 900), isDesktop: true),
          const Size(76.5, 38.25));
    });

    test('portrait crop includes both long aspect and narrow height-fit cases',
        () {
      for (final source in [const Size(100, 400), const Size(160, 320)]) {
        final display = StickerBubbleLayout.imageSize(source,
            screenSize: const Size(390, 800), availableWidth: 280);
        _expectSize(display, const Size(92, 160));
        expect(StickerBubbleLayout.imageFit(source, display), BoxFit.cover);
      }
      final ordinary = StickerBubbleLayout.imageSize(const Size(100, 170),
          availableWidth: 375);
      _expectSize(ordinary, const Size(160 * 100 / 170, 160));
      expect(StickerBubbleLayout.imageFit(const Size(100, 170), ordinary),
          BoxFit.contain);
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(100, 400),
              screenSize: const Size(1200, 900),
              availableWidth: 1000,
              isDesktop: true),
          const Size(92, 190));
    });

    test('very wide images retain their ratio instead of becoming a square',
        () {
      final display = StickerBubbleLayout.imageSize(const Size(3000, 100),
          availableWidth: 375);
      _expectSize(display, const Size(144, 4.8));
      expect(StickerBubbleLayout.imageFit(const Size(3000, 100), display),
          BoxFit.contain);
    });

    test('parent bounds also constrain normal, cropped, and unknown content',
        () {
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(320, 160),
              screenSize: const Size(320, 812), availableWidth: 80),
          const Size(43.2, 21.6));
      _expectSize(
          StickerBubbleLayout.imageSize(const Size(100, 400),
              availableWidth: 80, availableHeight: 100),
          const Size(43.2, 100));
      _expectSize(
          StickerBubbleLayout.placeholderSize(
              availableWidth: 80, availableHeight: 30),
          const Size.square(30));
    });

    test('invalid intrinsic dimensions use the same unknown-content frame', () {
      for (final source in [
        Size.zero,
        const Size(-1, 20),
        const Size(double.nan, 20),
        const Size(20, double.infinity),
      ]) {
        expect(StickerBubbleLayout.isValidSize(source), isFalse);
        _expectSize(StickerBubbleLayout.imageSize(source, availableWidth: 280),
            const Size.square(144));
        expect(StickerBubbleLayout.imageFit(source, const Size.square(144)),
            BoxFit.contain);
      }
    });
  });
}
