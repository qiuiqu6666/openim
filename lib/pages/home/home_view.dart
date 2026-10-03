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
import 'home_logic.dart';
import 'glass_bottom_nav_bar.dart';
import '../../widgets/theme_aware_page.dart';
import '../../core/controller/im_controller.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

enum _MainTab { messages, groups, contacts, wallet, me }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final logic = Get.find<HomeLogic>();
  final PersistentTabController _tabController =
      PersistentTabController(initialIndex: 0);
  final ValueNotifier<int> _activeTabIndex = ValueNotifier<int>(0);
  final conversationLogic = Get.find<ConversationLogic>();
  bool _profileImagesWarmed = false;
  Worker? _avatarWorker;
  String? _warmedAvatarUrl;

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
    _avatarWorker?.dispose();
    _activeTabIndex.dispose();
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = AppTokens.accent;
    final inactiveColor = AppTokens.textSecondary(dark: dark);
    return [
      PersistentTabConfig(
        screen: ThemeAwarePage(builder: (_) => ConversationPage()),
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
        screen:
            ThemeAwarePage(builder: (_) => ConversationPage(groupChats: true)),
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
        screen: ThemeAwarePage(builder: (_) => ContactsPage()),
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
        screen: WalletTabShell(activeTabIndexListenable: _activeTabIndex),
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

  void _jumpToWallet() {
    _activeTabIndex.value = 3;
    _tabController.jumpToTab(3);
  }

  int _unreadCount({required bool groupChats}) => conversationLogic.list
      .where((info) =>
          (groupChats ? info.isGroupChat : info.isSingleChat) &&
          !conversationLogic.isArchived(info))
      .fold(0, (count, info) => count + info.unreadCount);

  Widget _walletNavIcon(Color color) => ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcATop),
        child: Image.asset('assets/wallet.png', width: 24, height: 24),
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

  Widget _navIcon(String filename, Color color) => ColorFiltered(
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
      );

  Widget _setupIcon(Widget icon, int Function() unreadCount) {
    return Obx(() => Stack(
          alignment: Alignment.center,
          children: [
            icon,
            Positioned(
              top: 0,
              right: 0,
              child: Transform.translate(
                offset: const Offset(2, -2),
                child: UnreadCountView(count: unreadCount()),
              ),
            ),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Styles.c_FFFFFF,
      body: PersistentTabView(
        controller: _tabController,
        tabs: _tabs(context),
        onTabChanged: (index) => _activeTabIndex.value = index,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navBarBuilder: (config) => GlassBottomNavBar(config: config),
        navBarOverlap: const NavBarOverlap.full(),
        screenTransitionAnimation: const ScreenTransitionAnimation.none(),
      ),
    );
  }
}
