import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/host/wallet_navigation.dart';

void main() {
  test('wallet page route mirrors 99chat swipe-back thresholds', () {
    final route = AppMaterialPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    expect(route, isA<PageRouteBuilder<void>>());
    expect(route.edgeStartWidthPx, 24);
    expect(route.enableFullScreenBackGesture, isTrue);
    expect(route.transitionDuration, const Duration(milliseconds: 340));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 340));
  });
}
