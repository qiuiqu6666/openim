import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog keeps all 16 original faces in reference order', () {
    final stickers = ChatBuiltinStickerCatalog.stickers;
    expect(stickers, hasLength(16));
    expect(stickers.map((sticker) => sticker.fileName), [
      for (var index = 0; index < 16; index++)
        'ys${index.toString().padLeft(2, '0')}@2x.png',
    ]);
    expect(stickers.map((sticker) => sticker.id).toSet(), hasLength(16));
    expect(
        stickers.every((sticker) => sticker.label.trim().isNotEmpty), isTrue);
    expect(stickers.map((sticker) => sticker.fileName),
        isNot(contains('menu@2x.png')));
    expect(() => stickers.clear(), throwsUnsupportedError);
  });

  test('only exact registered IDs resolve to bundled sticker metadata', () {
    for (final sticker in ChatBuiltinStickerCatalog.stickers) {
      expect(ChatBuiltinStickerCatalog.byID(sticker.id), same(sticker));
      expect(sticker.assetPath,
          '${ChatBuiltinStickerCatalog.assetDirectory}/${sticker.fileName}');
    }
    expect(ChatBuiltinStickerCatalog.byID('menu'), isNull);
    expect(ChatBuiltinStickerCatalog.byID('ys00@2x.png'), isNull);
    expect(ChatBuiltinStickerCatalog.byID('99chat_4351_ys16'), isNull);
    expect(ChatBuiltinStickerCatalog.byID('../ys00@2x.png'), isNull);
  });

  test('all 17 originals are bundled unchanged and decode at their actual size',
      () async {
    final paths = {
      'menu@2x.png': ChatBuiltinStickerCatalog.menuAssetPath,
      for (final sticker in ChatBuiltinStickerCatalog.stickers)
        sticker.fileName: sticker.assetPath,
    };
    expect(paths.keys, unorderedEquals(_sourceHashes.keys));
    for (final entry in paths.entries) {
      final data = await rootBundle.load(entry.value);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(sha256.convert(bytes).toString(), _sourceHashes[entry.key],
          reason: '${entry.key} must retain its reference artwork bytes');
      // PNG's true-colour-with-alpha type retains the transparent background.
      expect(bytes[25], 6, reason: entry.key);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final expected = ChatBuiltinStickerCatalog.stickers
              .where((sticker) => sticker.fileName == entry.key)
              .firstOrNull;
          expect(frame.image.width,
              expected?.width ?? ChatBuiltinStickerCatalog.imageWidth,
              reason: entry.key);
          expect(frame.image.height,
              expected?.height ?? ChatBuiltinStickerCatalog.imageHeight,
              reason: entry.key);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
  });
}

// Independent SHA256 of reference revision d7c3c655's original 4351 assets.
const _sourceHashes = {
  'menu@2x.png':
      'af75702a361541ce78b80f2e7e052dd40464a57e46bac8fdb9a8f9569aa30e61',
  'ys00@2x.png':
      '8a7f7f3be4db16b79a183d09ecfb7e6dc89ed2f771020f35f70e3596c4e34083',
  'ys01@2x.png':
      '50249dd980023b66183bae39fb52fb524a683b06d63a2389f31b56ee9213d183',
  'ys02@2x.png':
      '50d439b31741ae16458b8c366980c4be2c46b446e410602ca7a184367ca97f6f',
  'ys03@2x.png':
      'ab9997fad1bf36d2bcfdee0306419fa111c3d03a048f4911adb8397c109db983',
  'ys04@2x.png':
      '752d0e6d0c8ebdbb47732076d0771da0e1bc9af286b1f4f03add329b54d87dcf',
  'ys05@2x.png':
      '7e2835e3408f27f35542290a9ecec6b84e1c1798be230befb8fa7a318a6e2c61',
  'ys06@2x.png':
      'ace1eb1a1045b915276de8d3dbbc56d2a817cd06cab1794db166256497c79ef9',
  'ys07@2x.png':
      'e2f7f38c138ebba4fbb73249e0b84697f67ebfa2812b159265c470030ed02843',
  'ys08@2x.png':
      '2e5fa08c4ac335b24a7c218d12f50e3297053f79358ee65979515dd535c8bdb5',
  'ys09@2x.png':
      '64ade398f15c07ee70e9ed819a15c555a25255ac1214fa374cd32b316181b475',
  'ys10@2x.png':
      '3ec494e2cb712be518dd78b98b7dfbffc131ef49fe7e74b5d5f973109c27c3e8',
  'ys11@2x.png':
      'e2d1e22dc41366ef691422d8a53dff3564d2428a3317e9be2a34e7401238e415',
  'ys12@2x.png':
      'b4d2a1646666cb4170dd190fc211110bd89cc0d185a1d84b4462f7f4bf3160f0',
  'ys13@2x.png':
      '7fcd64a1fa30a4648fb2ea6ec138db04d5b53f9504abef6fed8af06cb54e7dd6',
  'ys14@2x.png':
      '59efdbd83fa945e0eb73cca2ac60b4b3122f4ed9085bf2bd082c7eb0dad6d7b5',
  'ys15@2x.png':
      '733769dabba94e82eaa9154301b35329a447afe0b60d1f65fb48ba2c7816d197',
};
