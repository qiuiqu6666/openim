import 'package:flutter/material.dart';

import '../../../mine/settings/widgets/settings_widgets.dart';
import '../../localization/ai_assistant_i18n.dart';

/// AI actions reuse the app's existing 99chat Cupertino action sheet.
class AiMoreSheet {
  const AiMoreSheet._();

  static Future<String?> show(BuildContext context) {
    final i18n = AiAssistantI18n.of(context);
    return showSettingsActionSheet<String>(context, title: '', actions: [
      SettingsAction(
        i18n.t(
            zhHans: '好友名片',
            zhHant: '好友名片',
            en: 'Friend card',
            ja: '友だちの名刺',
            ko: '친구 명함'),
        'friend',
      ),
      SettingsAction(
        i18n.t(zhHans: '群聊', zhHant: '群聊', en: 'Group', ja: 'グループ', ko: '그룹'),
        'group',
      ),
    ]);
  }

  static Future<String?> overflow(BuildContext context) {
    final i18n = AiAssistantI18n.of(context);
    return showSettingsActionSheet<String>(context, title: '', actions: [
      SettingsAction(
        i18n.t(
            zhHans: '清空记录',
            zhHant: '清空紀錄',
            en: 'Clear history',
            ja: '履歴を消去',
            ko: '기록 지우기'),
        'clear',
        destructive: true,
      ),
    ]);
  }

  static Future<String?> copy(BuildContext context) {
    final i18n = AiAssistantI18n.of(context);
    return showSettingsActionSheet<String>(context, title: '', actions: [
      SettingsAction(
        i18n.t(zhHans: '复制', zhHant: '複製', en: 'Copy', ja: 'コピー', ko: '복사'),
        'copy',
      ),
    ]);
  }
}
