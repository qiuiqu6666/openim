import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  _walletHomeVisualHierarchyContract();
  test('Wallet and Mine share the same main-tab title treatment', () {
    final wallet =
        File('lib/pages/wallet/wallet_tab_shell.dart').readAsStringSync();
    final mine = File('lib/pages/mine/widgets/mine_profile_view.dart')
        .readAsStringSync();
    final shared = File('lib/pages/home/widgets/main_tab_title.dart')
        .readAsStringSync();
    final appTokens = File('openim_common/lib/src/res/app_tokens.dart')
        .readAsStringSync();

    expect(shared, contains('class MainTabTitle'));
    expect(wallet, contains('title: MainTabTitle('));
    expect(mine, contains('title: MainTabTitle('));
    expect(mine, isNot(contains('class _MineMainTabTitle')));
    expect(wallet, isNot(contains('theme.primaryColor')));
    expect(shared, contains('AppTokens.accent'));
    expect(shared, contains('AppTokens.mainTabIndicatorWidth'));
    expect(shared, contains('AppTokens.mainTabIndicatorHeight'));
    expect(shared, contains('AppTokens.mainTabIndicatorDotSize'));
    expect(shared, contains('AppTokens.mainTabTitleVerticalOffset'));
    expect(
      appTokens,
      contains('static const double mainTabTitleVerticalOffset = -2;'),
    );
  });

  test(
    'Wallet consumes the host bottom-tab inset exactly once for invite card',
    () {
      final walletShell =
          File('lib/pages/wallet/wallet_tab_shell.dart').readAsStringSync();
      final walletScreen =
          File('lib/pages/wallet/wallet_screen.dart').readAsStringSync();

      // PersistentTabView exposes the bottom-tab occupied area via MediaQuery.
      // SafeArea must consume it once; an extra 56px lift leaves a visible gap.
      expect(walletShell, isNot(contains('removeBottom: true')));
      expect(walletShell, contains('SafeArea('));
      expect(walletShell, contains('bottom: true'));
      expect(
        walletShell,
        isNot(contains(
          'padding: const EdgeInsets.only(bottom: kBottomNavigationBarHeight)',
        )),
      );
      expect(walletScreen, contains('_InviteFriendCard'));
      expect(walletScreen, contains('SizedBox(height: 8.h99)'));
      expect(walletScreen, contains("'assets/img/invite.webp'"));
      expect(walletScreen, contains("'assets/img/invite2.webp'"));
    },
  );

  test(
    'Wallet invite artwork remains bundled through the shared asset folder',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(File('assets/img/invite.webp').existsSync(), isTrue);
      expect(File('assets/img/invite2.webp').existsSync(), isTrue);
      expect(pubspec, contains('- assets/img/'));
    },
  );
}

// Wallet-home visual hierarchy contract. Keep the main actions readable and
// visually consistent with the premium card treatment used by the page.
void _walletHomeVisualHierarchyContract() {
  test('Wallet quick actions keep a clear one-row four-column hierarchy', () {
    final walletScreen =
        File('lib/pages/wallet/wallet_screen.dart').readAsStringSync();
    final artwork =
        File('lib/pages/wallet/wallet_action_artwork.dart').readAsStringSync();

    expect(
      walletScreen,
      contains('final actionBarHeight = (cardWidth * 0.235).clamp(90.0, 112.0);'),
    );
    expect(artwork, contains('static const double iconSize = 44;'));
    expect(artwork, contains('static const double titleFontSize = 14;'));
    expect(artwork, contains('static const double subtitleFontSize = 11;'));
    expect(artwork, contains('fontWeight: FontWeight.w700'));
    expect(artwork, contains('fontWeight: FontWeight.w500'));
    expect(artwork, isNot(contains('FittedBox(')));
  });

  test('Wallet asset list uses the same clean premium card language', () {
    final walletScreen =
        File('lib/pages/wallet/wallet_screen.dart').readAsStringSync();

    expect(walletScreen, isNot(contains('class _CoinListHeaderDecorPainter')));
    expect(walletScreen, contains('BorderRadius.circular(AppTokens.rXl.r99)'));
    expect(walletScreen, contains('BorderRadius.circular(AppTokens.rPill.r99)'));
  });

  test('Wallet quick actions use one restrained finance palette', () {
    final artwork =
        File('lib/pages/wallet/wallet_action_artwork.dart').readAsStringSync();
    final walletScreen =
        File('lib/pages/wallet/wallet_screen.dart').readAsStringSync();

    expect(
      artwork,
      contains('static const Color actionAccent = Color(0xFF9A7042);'),
    );
    expect(
      artwork,
      contains('static const Color actionSurface = Color(0xFFF7F2EA);'),
    );
    expect(artwork, isNot(contains('final colors = switch (action)')));
    for (final legacyColor in <String>[
      '0xFF49D6AD',
      '0xFF16B889',
      '0xFFFF8C86',
      '0xFFF06464',
      '0xFF64BFFF',
      '0xFF3A8FF5',
      '0xFFA78BFA',
      '0xFF8257E8',
    ]) {
      expect(artwork, isNot(contains(legacyColor)));
    }
    for (final coldBlue in <String>[
      '0xFF3B82F6',
      '0xFF2563EB',
      '0xFFF3F6FA',
    ]) {
      expect(artwork, isNot(contains(coldBlue)));
    }
    expect(walletScreen, contains('const Color(0xFFF5EFE6)'));
    expect(walletScreen, contains('const Color(0xFF8E6B43)'));
  });
}
