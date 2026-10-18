import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/home/wallet_home_view.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_tokens.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_poster.dart';
import '../../wallet/home/wallet_home_test_support.dart';
import 'support.dart';

void main() {
  const output = String.fromEnvironment('WALLET_POSTER_CAPTURE');
  testWidgets('wallet poster sits after assets and exports actual layout',
      skip: output.isEmpty, (t) async {
    final loader = FontLoader('PosterCJK');
    loader.addFont(Future.value(ByteData.sublistView(
        File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync())));
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final key = GlobalKey();
    final source = FakeSource();
    final controller = await loadedHomeController();
    await pumpWalletHome(t,
        controller: controller,
        size: const Size(390, 844),
        fontFamily: 'PosterCJK',
        boundaryKey: key,
        page: WalletHomeView(compensationSource: source));
    await t.pumpAndSettle();
    await settleWalletHomeImages(t);
    await t.runAsync(() => precacheImage(
        const AssetImage(CompensationTokens.walletBanner),
        t.element(find.byType(CompensationPoster))));
    await t.pumpAndSettle();
    expect(find.byType(CompensationPoster), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(output).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await t.pumpWidget(const SizedBox());
  });
}
