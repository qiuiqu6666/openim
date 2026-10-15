import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../contacts/contacts_view.dart';
import '../conversation/conversation_view.dart';
import '../conversation/conversation_logic.dart';
import '../mine/mine_view.dart';
import '../mine/widgets/mine_hot_eco.dart';
import '../wallet/wallet_tab_shell.dart';
import '../wallet/entry/wallet_entry_coordinator.dart';
import 'home_logic.dart';
import 'glass_bottom_nav_bar.dart';
import 'navigation/home_navigation_tokens.dart';
import 'navigation/home_navigation_icon.dart';
import 'navigation/animated_home_icon.dart';
import '../../widgets/theme_aware_page.dart';
import '../../core/controller/im_controller.dart';
import '../../core/controller/app_controller.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

enum _MainTab { messages, groups, contacts, wallet, me }

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.walletEntry});

  /// The home route owns and disposes its wallet entry coordinator.
  final WalletEntryCoordinator? walletEntry;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final logic = Get.find<HomeLogic>();
  final PersistentTabController _tabController =
      PersistentTabController(initialIndex: 0);
  final ValueNotifier<int> _activeTabIndex = ValueNotifier<int>(0);
  late final WalletEntryCoordinator _walletEntry =
      widget.walletEntry ?? WalletEntryCoordinator();
  final conversationLogic = Get.find<ConversationLogic>();
  bool _profileImagesWarmed = false;
  Worker? _avatarWorker;
  String? _warmedAvatarUrl;
  final _conversationEditBars = <bool, Widget?>{};
  final _inlineSearchModes = <int, bool>{};
  final _editBarRevision = ValueNotifier<int>(0);
  AppController? _notificationNavigation;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<AppController>()) {
      _notificationNavigation = Get.find<AppController>();
      _notificationNavigation!.registerMessageListNavigation(_showMessageList);
    }
  }

  void _showMessageList() {
    if (mounted) _tabController.jumpToTab(0);
  }

  void _setConversationEditBar(bool groupChats, Widget? bar) {
    if (!mounted) return;
    _conversationEditBars[groupChats] = bar;
    _editBarRevision.value++;
  }

  void _setInlineSearchMode(int tabIndex, bool searching) {
    if (!mounted) return;
    _inlineSearchModes[tabIndex] = searching;
    _editBarRevision.value++;
  }

  void _warmAvatar(String? url) {
    if (!mounted || url == _warmedAvatarUrl || !IMUtils.isUrlValid(url)) return;
    _warmedAvatarUrl = url;
    precacheImage(ExtendedNetworkImageProvider(url!, cache: false), context,
        onError: (_, __) {
      if (_warmedAvatarUrl == url) _warmedAvatarUrl = null;
    });
  }

  @override
  void dispose() {
    _notificationNavigation?.unregisterMessageListNavigation(_showMessageList);
    _walletEntry.dispose();
    _avatarWorker?.dispose();
    _activeTabIndex.dispose();
    _editBarRevision.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profileImagesWarmed) return;
    _profileImagesWarmed = true;
    final userInfo = Get.find<IMController>().userInfo;
    _warmAvatar(userInfo.value.faceURL);
    _avatarWorker = ever(userInfo, (user) => _warmAvatar(user.faceURL));
    // Start decoding while the initial chat tab is visible.
    for (final image in MineHotEcoSection.imageProviders) {
      precacheImage(image, context);
    }
  }

  List<PersistentTabConfig> _tabs(BuildContext context) {
    final routeCurrent = ModalRoute.of(context)?.isCurrent != false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = AppTokens.accent;
    final inactiveColor = AppTokens.textSecondary(dark: dark);
    return [
      PersistentTabConfig(
        screen: ThemeAwarePage(
            builder: (_) => ValueListenableBuilder<int>(
                valueListenable: _activeTabIndex,
                builder: (_, index, __) => ConversationPage(
                    liveUpdatesActive: routeCurrent && index == 0,
                    onSearchModeChanged: (searching) =>
                        _setInlineSearchMode(0, searching),
                    onEditActionBarChanged: (bar) =>
                        _setConversationEditBar(false, bar)))),
        item: ItemConfig(
          icon: _setupIcon(
              _navIcon('nav_chat_active_99chat.png', selectedColor),
              () => _unreadCount(groupChats: false)),
          inactiveIcon: _setupIcon(
              _navIcon('nav_chat_99chat.png', inactiveColor),
              () => _unreadCount(groupChats: false)),
          title: _mainTabTitle(context, _MainTab.messages),
          textStyle: Styles.ts_0089FF_10sp_semibold,
        ),
      ),
      PersistentTabConfig(
        screen: ThemeAwarePage(
            builder: (_) => ValueListenableBuilder<int>(
                valueListenable: _activeTabIndex,
                builder: (_, index, __) => ConversationPage(
                    groupChats: true,
                    liveUpdatesActive: routeCurrent && index == 1,
                    onSearchModeChanged: (searching) =>
                        _setInlineSearchMode(1, searching),
                    onEditActionBarChanged: (bar) =>
                        _setConversationEditBar(true, bar)))),
        item: ItemConfig(
          icon: _setupIcon(_navIcon('nav_group_conv_99chat.png', selectedColor),
              () => _unreadCount(groupChats: true)),
          inactiveIcon: _setupIcon(
              _navIcon('nav_group_conv_99chat.png', inactiveColor),
              () => _unreadCount(groupChats: true)),
          title: _mainTabTitle(context, _MainTab.groups),
          textStyle: Styles.ts_0089FF_10sp_semibold,
        ),
      ),
      PersistentTabConfig(
        screen: ThemeAwarePage(
            builder: (_) => ContactsPage(
                onSearchModeChanged: (searching) =>
                    _setInlineSearchMode(2, searching))),
        item: ItemConfig(
          icon: _setupIcon(
              _navIcon('nav_contact_active_99chat.png', selectedColor),
              () => logic.unhandledCount.value),
          inactiveIcon: _setupIcon(
              _navIcon('nav_contact_99chat.png', inactiveColor),
              () => logic.unhandledCount.value),
          title: _mainTabTitle(context, _MainTab.contacts),
          textStyle: Styles.ts_0089FF_10sp_semibold,
        ),
      ),
      PersistentTabConfig(
        screen: WalletTabShell(
          activeTabIndexListenable: _activeTabIndex,
          entry: _walletEntry,
          onRetryEntry: () => _enterWallet(() {}),
        ),
        item: ItemConfig(
          icon: _walletNavIcon(selectedColor),
          inactiveIcon: _walletNavIcon(inactiveColor),
          title: _mainTabTitle(context, _MainTab.wallet),
          textStyle: Styles.ts_0089FF_10sp_semibold,
        ),
      ),
      PersistentTabConfig(
        screen: ThemeAwarePage(
          builder: (_) => MinePage(
            onWalletTap: _jumpToWallet,
          ),
        ),
        item: ItemConfig(
          icon: _navIcon('nav_profile_active_99chat.png', selectedColor),
          inactiveIcon: _navIcon('nav_profile_99chat.png', inactiveColor),
          title: _mainTabTitle(context, _MainTab.me),
          textStyle: Styles.ts_0089FF_10sp_semibold,
        ),
      ),
    ];
  }

  Future<void> _jumpToWallet() => _enterWallet(() {
        _activeTabIndex.value = 3;
        _tabController.jumpToTab(3);
      });

  void _selectMainTab(int index, ValueChanged<int> select) {
    if (index == 3) {
      _enterWallet(() => select(index));
      return;
    }
    _walletEntry.cancel();
    select(index);
  }

  Future<void> _enterWallet(VoidCallback select) async {
    select();
    await _walletEntry.enter(
      context,
      isActive: () => mounted && _activeTabIndex.value == 3,
      onAllowed: () {},
    );
  }

  int _unreadCount({required bool groupChats}) {
    final snapshot = conversationLogic.feedSnapshot;
    return groupChats ? snapshot.groupUnread : snapshot.singleUnread;
  }

  Widget _walletNavIcon(Color color) => AnimatedHomeIcon(
        selected: color == AppTokens.accent,
        motion: HomeIconMotion.wallet,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcATop),
          child: Image.asset('assets/wallet.png', width: 24, height: 24),
        ),
      );

  String _mainTabTitle(BuildContext context, _MainTab tab) {
    final locale = Localizations.localeOf(context);
    final language = locale.languageCode;
    final traditionalChinese = language == 'zh' &&
        (locale.scriptCode == 'Hant' ||
            const {'TW', 'HK', 'MO'}.contains(locale.countryCode));
    if (traditionalChinese) {
      return switch (tab) {
        _MainTab.messages => '訊息',
        _MainTab.groups => '群聊',
        _MainTab.contacts => '通訊錄',
        _MainTab.wallet => '錢包',
        _MainTab.me => '我的',
      };
    }
    return switch (language) {
      'zh' => switch (tab) {
          _MainTab.messages => '消息',
          _MainTab.groups => '群聊',
          _MainTab.contacts => '通讯录',
          _MainTab.wallet => '钱包',
          _MainTab.me => '我的',
        },
      'ja' => switch (tab) {
          _MainTab.messages => 'メッセージ',
          _MainTab.groups => 'グループ',
          _MainTab.contacts => '連絡先',
          _MainTab.wallet => 'ウォレット',
          _MainTab.me => 'マイページ',
        },
      'ko' => switch (tab) {
          _MainTab.messages => '메시지',
          _MainTab.groups => '그룹',
          _MainTab.contacts => '연락처',
          _MainTab.wallet => '지갑',
          _MainTab.me => '내 정보',
        },
      _ => switch (tab) {
          _MainTab.messages => 'Messages',
          _MainTab.groups => 'Groups',
          _MainTab.contacts => 'Contacts',
          _MainTab.wallet => 'Wallet',
          _MainTab.me => 'Me',
        },
    };
  }

  Widget _navIcon(String filename, Color color) => AnimatedHomeIcon(
        selected: color == AppTokens.accent,
        motion: filename.contains('contact')
            ? HomeIconMotion.contact
            : filename.contains('group')
                ? HomeIconMotion.group
                : filename.contains('profile')
                    ? HomeIconMotion.profile
                    : HomeIconMotion.message,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcATop),
          child: Image.asset('assets/images/$filename',
              package: 'openim_common',
              width: 24,
              height: 24,
              errorBuilder: (_, __, ___) => AppIcon(
                    kind: filename.contains('contact')
                        ? AppIconKind.contacts
                        : filename.contains('group')
                            ? AppIconKind.groupChat
                            : filename.contains('profile')
                                ? AppIconKind.profile
                                : AppIconKind.singleChat,
                    color: color,
                  )),
        ),
      );

  Widget _setupIcon(Widget icon, int Function() unreadCount) {
    return Obx(() => HomeNavigationIcon(icon: icon, count: unreadCount()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: PersistentTabView(
        controller: _tabController,
        navBarHeight: HomeNavigationTokens.height,
        tabs: _tabs(context),
        onTabChanged: (index) {
          _activeTabIndex.value = index;
          logic.switchTab(index);
        },
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navBarBuilder: (config) => ValueListenableBuilder<int>(
            valueListenable: _editBarRevision,
            builder: (context, __, ___) {
              if (_inlineSearchModes[config.selectedIndex] == true) {
                return const SizedBox.shrink();
              }
              final editBar = config.selectedIndex < 2
                  ? _conversationEditBars[config.selectedIndex == 1]
                  : null;
              if (editBar != null) {
                // Keep the same viewport when navigation becomes edit actions.
                // The action bar itself consumes the bottom safe area once.
                return SizedBox(
                  height: HomeNavigationTokens.height +
                      MediaQuery.paddingOf(context).bottom,
                  child: editBar,
                );
              }
              return GlassBottomNavBar(
                config: config,
                onItemSelected: (index) =>
                    _selectMainTab(index, config.onItemSelected),
              );
            }),
        navBarOverlap: const NavBarOverlap.full(),
        screenTransitionAnimation: const ScreenTransitionAnimation.none(),
      ),
    );
  }
}
