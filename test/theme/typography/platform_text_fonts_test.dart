import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/widgets/wallet_99chat_tokens.dart'
    as wallet;
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_composer_palette.dart';

void main() {
  for (final platform in TargetPlatform.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'composer and wallet keep platform fonts $platform/$brightness',
          (tester) async {
        late TextStyle inputStyle;
        late TextStyle hintStyle;
        late String? walletFamily;
        late List<String>? walletFallback;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: platform, brightness: brightness),
          home: Builder(builder: (context) {
            inputStyle = chatComposerTextStyle(context);
            hintStyle = chatComposerTextStyle(context, hint: true);
            walletFamily = wallet.AppTokens.fontFamilyOf(context);
            walletFallback = wallet.AppTokens.fontFamilyFallbackOf(context);
            return const SizedBox.shrink();
          }),
        ));

        final expectedFamily = switch (platform) {
          TargetPlatform.windows => 'Microsoft YaHei UI',
          TargetPlatform.macOS => 'PingFang SC',
          TargetPlatform.linux => 'Noto Sans CJK SC',
          _ => null,
        };
        final expectedFallback = switch (platform) {
          TargetPlatform.windows => ['Microsoft YaHei', 'Segoe UI'],
          TargetPlatform.macOS => ['PingFang TC', 'Hiragino Sans GB'],
          TargetPlatform.linux => ['Noto Sans CJK TC', 'WenQuanYi Micro Hei'],
          _ => null,
        };
        expect(inputStyle.fontFamily, expectedFamily);
        expect(inputStyle.fontFamilyFallback, expectedFallback);
        expect(walletFamily, expectedFamily);
        expect(walletFallback, expectedFallback);
        expect(hintStyle.fontFamily, expectedFamily);
        expect(hintStyle.fontFamilyFallback, expectedFallback);

        // Keep the established Chinese/Latin composer metrics in both themes.
        expect(inputStyle.inherit, false);
        expect(inputStyle.fontSize, 16);
        expect(inputStyle.height, 1.3);
        expect(inputStyle.fontWeight, FontWeight.w400);
        expect(inputStyle.textBaseline, TextBaseline.alphabetic);
        expect(inputStyle.color,
            AppTokens.textPrimary(dark: brightness == Brightness.dark));
        expect(hintStyle.color,
            AppTokens.textSecondary(dark: brightness == Brightness.dark));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
