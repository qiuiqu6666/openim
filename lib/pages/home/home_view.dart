import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../contacts/contacts_view.dart';
import '../conversation/conversation_view.dart';
import '../conversation/conversation_logic.dart';
import '../mine/mine_view.dart';
import 'home_logic.dart';
import 'glass_bottom_nav_bar.dart';
import '../../widgets/theme_aware_page.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

class HomePage extends StatelessWidget {
  final logic = Get.find<HomeLogic>();
  final conversationLogic = Get.find<ConversationLogic>();
  HomePage({super.key});

  List<PersistentTabConfig> _tabs(BuildContext context) => [
        PersistentTabConfig(
          screen: ThemeAwarePage(builder: (_) => ConversationPage()),
          item: ItemConfig(
            icon: _setupIcon(
                _navIcon('nav_chat_active_99chat.png',
                    Styles.c_0089FF),
                () => _unreadCount(groupChats: false)),
            inactiveIcon: _setupIcon(
                _navIcon('nav_chat_99chat.png',
                    Theme.of(context).colorScheme.onSurfaceVariant),
                () => _unreadCount(groupChats: false)),
            title: StrRes.singleChat,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
        PersistentTabConfig(
          screen: ThemeAwarePage(
              builder: (_) => ConversationPage(groupChats: true)),
          item: ItemConfig(
            icon: _setupIcon(
                _navIcon('nav_group_conv_99chat.png',
                    Styles.c_0089FF),
                () => _unreadCount(groupChats: true)),
            inactiveIcon: _setupIcon(
                _navIcon('nav_group_conv_99chat.png',
                    Theme.of(context).colorScheme.onSurfaceVariant),
                () => _unreadCount(groupChats: true)),
            title: StrRes.groupChat,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
        PersistentTabConfig(
          screen: ThemeAwarePage(builder: (_) => ContactsPage()),
          item: ItemConfig(
            icon: _setupIcon(
                _navIcon('nav_contact_active_99chat.png',
                    Styles.c_0089FF),
                () => logic.unhandledCount.value),
            inactiveIcon: _setupIcon(
                _navIcon('nav_contact_99chat.png',
                    Theme.of(context).colorScheme.onSurfaceVariant),
                () => logic.unhandledCount.value),
            title: StrRes.contacts,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
        PersistentTabConfig(
          screen: ThemeAwarePage(builder: (_) => MinePage()),
          item: ItemConfig(
            icon: _navIcon('nav_profile_active_99chat.png',
                Styles.c_0089FF),
            inactiveIcon: _navIcon('nav_profile_99chat.png',
                Theme.of(context).colorScheme.onSurfaceVariant),
            title: StrRes.mine,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
      ];

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
