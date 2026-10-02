import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../contacts/contacts_view.dart';
import '../conversation/conversation_view.dart';
import '../conversation/conversation_logic.dart';
import '../mine/mine_view.dart';
import '../mine/widgets/mine_hot_eco.dart';
import 'home_logic.dart';
import 'glass_bottom_nav_bar.dart';
import '../../widgets/theme_aware_page.dart';
import '../../core/controller/im_controller.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final logic = Get.find<HomeLogic>();
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
          title: StrRes.singleChat,
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
          title: StrRes.groupChat,
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
          title: StrRes.contacts,
          textStyle: Styles.ts_0089FF_10sp_semibold,
        ),
      ),
      PersistentTabConfig(
        screen: ThemeAwarePage(builder: (_) => MinePage()),
        item: ItemConfig(
          icon: _navIcon('nav_profile_active_99chat.png', selectedColor),
          inactiveIcon: _navIcon('nav_profile_99chat.png', inactiveColor),
          title: StrRes.mine,
          textStyle: Styles.ts_0089FF_10sp_semibold,
        ),
      ),
    ];
  }

  int _unreadCount({required bool groupChats}) => conversationLogic.list
      .where((info) =>
          (groupChats ? info.isGroupChat : info.isSingleChat) &&
          !conversationLogic.isArchived(info))
      .fold(0, (count, info) => count + info.unreadCount);

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
        tabs: _tabs(context),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navBarBuilder: (config) => GlassBottomNavBar(config: config),
        navBarOverlap: const NavBarOverlap.full(),
        screenTransitionAnimation: const ScreenTransitionAnimation.none(),
      ),
    );
  }
}
