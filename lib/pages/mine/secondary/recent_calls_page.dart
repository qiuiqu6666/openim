import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../settings/widgets/settings_widgets.dart';

enum _RecentCallTab { all, missed }

class RecentCallsPage extends StatefulWidget {
  const RecentCallsPage({
    super.key,
    this.onStartCall,
  });

  final void Function(String userId, bool video)? onStartCall;

  @override
  State<RecentCallsPage> createState() => _RecentCallsPageState();
}

class _RecentCallsPageState extends State<RecentCallsPage> {
  _RecentCallTab _tab = _RecentCallTab.all;

  Future<void> _startNewCall() async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.crateGroup,
    );
    if (!mounted || result == null) return;
    final picked = IMUtils.convertSelectContactsResultToUserInfo(result);
    if (picked == null || picked.isEmpty) return;

    final type = await showSettingsActionSheet<String>(
      context,
      title: settingsText(context, zh: '开始新通话', en: 'Start a New Call'),
      actions: [
        SettingsAction(settingsText(context, zh: '语音通话', en: 'Audio Call'), 'audio'),
        SettingsAction(settingsText(context, zh: '视频通话', en: 'Video Call'), 'video'),
      ],
    );
    if (!mounted || type == null) return;

    final userId = picked.first.userID?.trim() ?? '';
    if (userId.isEmpty) return;
    final starter = widget.onStartCall;
    if (starter == null) {
      showUnavailableSettingsAction(
        context,
        type == 'video'
            ? settingsText(context, zh: '视频通话', en: 'Video Call')
            : settingsText(context, zh: '语音通话', en: 'Audio Call'),
      );
      return;
    }
    starter(userId, type == 'video');
  }

  String _tabLabel(_RecentCallTab tab) => switch (tab) {
        _RecentCallTab.all => settingsText(context, zh: '全部', en: 'All'),
        _RecentCallTab.missed => settingsText(context, zh: '未接', en: 'Missed'),
      };

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final background = AppTokens.background(dark: dark);
    final surface = AppTokens.surface(dark: dark);
    final text = AppTokens.textPrimary(dark: dark);
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: background,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: overlay,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: AppTokens.accent,
            ),
          ),
          title: Container(
            width: 164,
            height: 34,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2A2D33) : const Color(0xFFF1F2F5),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: _RecentCallTab.values.map((tab) {
                final selected = tab == _tab;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _tab = tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        _tabLabel(tab),
                        style: TextStyle(
                          color: text,
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: const [SizedBox(width: 12)],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _startNewCall,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.add_call,
                            size: 24,
                            color: AppTokens.accent,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              settingsText(
                                context,
                                zh: '开始新通话',
                                en: 'Start a New Call',
                              ),
                              style: const TextStyle(
                                color: AppTokens.accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SettingsEmptyState(
                  icon: _tab == _RecentCallTab.missed
                      ? Icons.phone_missed_outlined
                      : Icons.call_outlined,
                  title: _tab == _RecentCallTab.missed
                      ? settingsText(
                          context,
                          zh: '暂无未接记录',
                          en: 'No missed calls',
                        )
                      : settingsText(
                          context,
                          zh: '暂无通话记录',
                          en: 'No call records',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
