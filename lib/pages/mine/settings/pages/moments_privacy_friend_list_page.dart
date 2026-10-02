import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'moments_friend_picker_page.dart';

enum MomentsPrivacyListKind { blockedViewer, hiddenAuthor }

class MomentsPrivacyFriendListPage extends StatelessWidget {
  const MomentsPrivacyFriendListPage({
    super.key,
    required this.store,
    required this.kind,
    this.service = const StubSettingsService(),
  });

  final SettingsDraftStore store;
  final MomentsPrivacyListKind kind;
  final SettingsService service;

  Map<String, SettingsContactDraft> get _entries =>
      kind == MomentsPrivacyListKind.blockedViewer
          ? store.momentsHiddenFrom
          : store.momentsHiddenBy;

  String _title(BuildContext context) {
    final count = _entries.length;
    return kind == MomentsPrivacyListKind.blockedViewer
        ? settingsText(
            context,
            zh: '不让他(她)看我的朋友圈 ($count)',
            en: 'Hide My Posts From Others ($count)',
          )
        : settingsText(
            context,
            zh: '不看他(她)的朋友圈 ($count)',
            en: 'Hide Their Posts ($count)',
          );
  }

  String _emptyHint(BuildContext context) =>
      kind == MomentsPrivacyListKind.blockedViewer
          ? settingsText(
              context,
              zh: '把通讯录的某个朋友放到这里，选择「公开」这个可见范围发照片他（她）将无法看到。',
              en: 'Add a contact here. When you post with Public visibility, they will not see your moments.',
            )
          : settingsText(
              context,
              zh: '把通讯录的某个朋友放到这里，你将看不到他（她）发布的朋友圈动态。',
              en: 'Add a contact here. You will not see their moments in your feed.',
            );

  Future<void> _add(BuildContext context) async {
    final picked = await Navigator.of(context).push<List<SettingsContactDraft>>(
      MaterialPageRoute(
        builder: (_) => MomentsFriendPickerPage(
          title: settingsText(context, zh: '选择朋友', en: 'Select Friends'),
          initialSelectedIds: _entries.keys.toList(growable: false),
        ),
      ),
    );
    if (!context.mounted || picked == null) return;
    if (!service.isBackendAvailable) {
      await showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '朋友圈隐私设置', en: 'Moments privacy settings'),
      );
      return;
    }
    final ids = picked.map((item) => item.userId).toList(growable: false);
    if (kind == MomentsPrivacyListKind.blockedViewer) {
      await service.updateMomentsBlockedViewerIds(ids);
      if (context.mounted) store.replaceMomentsHiddenFrom(picked);
    } else {
      await service.updateMomentsHiddenAuthorIds(ids);
      if (context.mounted) store.replaceMomentsHiddenBy(picked);
    }
  }

  Future<void> _remove(BuildContext context, SettingsContactDraft entry) async {
    if (!service.isBackendAvailable) {
      await showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '朋友圈隐私设置', en: 'Moments privacy settings'),
      );
      return;
    }
    final next = _entries.values
        .where((item) => item.userId != entry.userId)
        .toList(growable: false);
    final ids = next.map((item) => item.userId).toList(growable: false);
    if (kind == MomentsPrivacyListKind.blockedViewer) {
      await service.updateMomentsBlockedViewerIds(ids);
      if (context.mounted) store.replaceMomentsHiddenFrom(next);
    } else {
      await service.updateMomentsHiddenAuthorIds(ids);
      if (context.mounted) store.replaceMomentsHiddenBy(next);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final dark = settingsIsDark(context);
          final values = _entries.values.toList(growable: false);
          return SettingsScaffold(
            title: _title(context),
            children: [
              if (values.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 72, 32, 24),
                  child: Column(
                    children: [
                      Text(
                        _emptyHint(context),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTokens.textSecondary(dark: dark),
                          fontSize: 15,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _buildAddButton(context, compact: false),
                    ],
                  ),
                )
              else ...[
                SettingsGroup(
                  margin: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < values.length; i++)
                      _FriendRow(
                        entry: values[i],
                        dark: dark,
                        showDivider: i < values.length - 1,
                        onRemove: () => _remove(context, values[i]),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Center(child: _buildAddButton(context, compact: true)),
                ),
              ],
            ],
          );
        },
      );

  Widget _buildAddButton(BuildContext context, {required bool compact}) {
    final dark = settingsIsDark(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _add(context),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: compact ? null : 220,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 48,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: settingsSurfaceAlt(dark),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTokens.border(dark: dark)),
          ),
          child: Text(
            settingsText(context, zh: '添加', en: 'Add'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTokens.textPrimary(dark: dark),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.entry,
    required this.dark,
    required this.showDivider,
    required this.onRemove,
  });

  final SettingsContactDraft entry;
  final bool dark;
  final bool showDivider;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTokens.surface(dark: dark),
          border: showDivider
              ? Border(
                  bottom: BorderSide(
                    color: AppTokens.border(dark: dark),
                    width: 0.7,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            AvatarView(
              url: entry.avatarUrl,
              text: entry.displayName,
              width: 44,
              height: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTokens.textPrimary(dark: dark),
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              tooltip: settingsText(context, zh: '移除', en: 'Remove'),
              onPressed: onRemove,
              icon: Icon(
                Icons.remove_circle_outline_rounded,
                color: AppTokens.textSecondary(dark: dark),
              ),
            ),
          ],
        ),
      );
}
