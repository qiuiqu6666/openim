import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
