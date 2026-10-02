import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_navigation.dart';
import '../widgets/settings_widgets.dart';

String storageFormatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 || value >= 100 ? 0 : 1)} ${units[index]}';
}

Widget storagePrimaryButton(
  BuildContext context, {
  required String label,
  required VoidCallback? onPressed,
  bool danger = false,
}) {
  final dark = settingsIsDark(context);
  return SizedBox(
    height: SettingsResponsive.controlHeight(context),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: danger ? settingsDanger(dark) : AppTokens.accent,
        foregroundColor: AppTokens.onAccent,
        disabledBackgroundColor: AppTokens.surfaceAlt(dark: dark),
        disabledForegroundColor: AppTokens.textSecondary(dark: dark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd),
        ),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );
}

Future<bool> showStorageConfirm(
  BuildContext context, {
  required String title,
  required String description,
  required String action,
  bool danger = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final dark = settingsIsDark(sheetContext);
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s6,
            AppTokens.s8,
            AppTokens.s6,
            AppTokens.s7,
          ),
          decoration: BoxDecoration(
            color: AppTokens.surface(dark: dark),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.rLg),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor:
                    (danger ? settingsDanger(dark) : AppTokens.accent)
                        .withValues(alpha: .1),
                child: Icon(
                  danger
                      ? Icons.delete_outline_rounded
                      : Icons.cleaning_services_outlined,
                  size: 32,
                  color: danger ? settingsDanger(dark) : AppTokens.accent,
                ),
              ),
              const SizedBox(height: AppTokens.s6),
              Text(title,
                  style: TextStyle(
                    color: AppTokens.textPrimary(dark: dark),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: AppTokens.s4),
              Text(description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTokens.textSecondary(dark: dark),
                    fontSize: 14,
                    height: 1.5,
                  )),
              const SizedBox(height: AppTokens.s8),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: SettingsResponsive.controlHeight(context),
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      style: TextButton.styleFrom(
                        backgroundColor: AppTokens.surfaceAlt(dark: dark),
                        foregroundColor: AppTokens.textPrimary(dark: dark),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTokens.rMd),
                        ),
                      ),
                      child:
                          Text(settingsText(context, zh: '取消', en: 'Cancel')),
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.s4),
                Expanded(
                  child: storagePrimaryButton(sheetContext,
                      label: action,
                      danger: danger,
                      onPressed: () => Navigator.pop(sheetContext, true)),
                ),
              ]),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

Future<void> showStorageComplete(BuildContext context, int bytes) =>
    openSettingsPage<void>(context, _StorageCompletePage(bytes: bytes));

class _StorageCompletePage extends StatelessWidget {
  const _StorageCompletePage({required this.bytes});

  final int bytes;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return SettingsScaffold(
      title: '',
      showLeading: false,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: AppTokens.accent.withValues(alpha: .12),
              child: const Icon(Icons.check_rounded,
                  size: 46, color: AppTokens.accent),
            ),
            const SizedBox(height: AppTokens.s7),
            Text(settingsText(context, zh: '清理完成', en: 'Cleanup complete'),
                style: TextStyle(
                  color: AppTokens.textPrimary(dark: dark),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: AppTokens.s4),
            Text(
              settingsText(context,
                  zh: '已释放 ${storageFormatBytes(bytes)} 存储空间',
                  en: 'Freed ${storageFormatBytes(bytes)} of storage'),
              style: TextStyle(color: AppTokens.textSecondary(dark: dark)),
            ),
          ],
        ),
      ),
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.s5, AppTokens.s3, AppTokens.s5, AppTokens.s6),
        child: SizedBox(
          width: double.infinity,
          child: storagePrimaryButton(context,
              label: settingsText(context, zh: '完成', en: 'Done'),
              onPressed: () => Navigator.of(context).pop()),
        ),
      ),
      children: const [],
    );
  }
}
