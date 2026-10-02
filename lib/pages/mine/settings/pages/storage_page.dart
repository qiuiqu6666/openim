import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:openim_common/openim_common.dart';
import 'package:path_provider/path_provider.dart';

import '../settings_navigation.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'chat_storage_page.dart';
import 'storage_media_repository.dart';
import 'storage_widgets.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key, required this.service});

  /// Kept for route compatibility. Storage calculation/cleanup is local-only
  /// and deliberately does not use backend SettingsService methods.
  final SettingsService service;

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  bool _loading = true;
  bool _loadError = false;
  bool _clearing = false;
  int _mediaBytes = 0;
  int _cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final usage = await _collectUsage();
      if (!mounted) return;
      setState(() {
        _mediaBytes = usage.mediaBytes;
        _cacheBytes = usage.cacheBytes;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  Future<_StorageUsage> _collectUsage() async {
    final appCache = await getApplicationCacheDirectory();
    final temp = await getTemporaryDirectory();
    final mediaRoots = <Directory>[
      Directory('${appCache.path}${Platform.pathSeparator}picture'),
      Directory('${appCache.path}${Platform.pathSeparator}video'),
      Directory('${appCache.path}${Platform.pathSeparator}file'),
      Directory('${Config.cachePath}outgoing_media'),
    ];

    var media = 0;
    for (final dir in mediaRoots) {
      media += await _directorySize(dir);
    }

    var cache = await _directorySizeExcluding(
      appCache,
      excludedTopLevelNames: const {'picture', 'video', 'file'},
    );
    if (temp.absolute.path != appCache.absolute.path) {
      cache += await _directorySize(temp);
    }

    return _StorageUsage(mediaBytes: media, cacheBytes: cache);
  }

  Future<int> _directorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<int> _directorySizeExcluding(
    Directory dir, {
    required Set<String> excludedTopLevelNames,
  }) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final child in dir.list(followLinks: false)) {
        final name = child.path.split(Platform.pathSeparator).last;
        if (excludedTopLevelNames.contains(name)) continue;
        if (child is File) {
          try {
            total += await child.length();
          } catch (_) {}
        } else if (child is Directory) {
          total += await _directorySize(child);
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> _clear() async {
    if (_clearing || _loading || _cacheBytes == 0) return;
    final before = _cacheBytes;
    final ok = await showStorageConfirm(
      context,
      title: settingsText(context, zh: '清理缓存', en: 'Clear Cache'),
      description: settingsText(
        context,
        zh: '将清理图片缩略图、临时文件等，共约 ${storageFormatBytes(before)}。不会删除聊天记录，可放心清理。',
        en: 'Clear thumbnails and temporary files (about ${storageFormatBytes(before)}). Chat messages will remain.',
      ),
      action: settingsText(context, zh: '清理', en: 'Clear'),
    );
    if (!ok || !mounted) return;

    setState(() => _clearing = true);
    try {
      await DefaultCacheManager().emptyCache();
      await _clearLocalCacheTargets();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _refreshUsage();
      if (!mounted) return;
      if (_loadError) throw const FileSystemException('Storage refresh failed');
      await showStorageComplete(context, before - _cacheBytes);
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(
          context,
          zh: '清理失败，请稍后重试',
          en: 'Failed to clear cache. Please try again later.',
        ),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearLocalCacheTargets() async {
    final appCache = await getApplicationCacheDirectory();
    final temp = await getTemporaryDirectory();

    await _deleteChildren(
      appCache,
      excludedTopLevelNames: const {'picture', 'video', 'file'},
    );
    if (temp.absolute.path != appCache.absolute.path) {
      await _deleteChildren(temp);
    }
  }

  Future<void> _deleteChildren(
    Directory dir, {
    Set<String> excludedTopLevelNames = const {},
  }) async {
    if (!await dir.exists()) return;
    await for (final child in dir.list(followLinks: false)) {
      final name = child.path.split(Platform.pathSeparator).last;
      if (excludedTopLevelNames.contains(name)) continue;
      try {
        await child.delete(recursive: true);
      } catch (_) {
        // Continue clearing other cache entries if one is locked by the OS.
      }
    }
  }

  void _openChatFiles({
    StorageMediaType? type,
    int minBytes = 0,
    int olderDays = 0,
  }) {
    openSettingsPage<void>(
      context,
      ChatStoragePage(
        initialType: type,
        initialMinBytes: minBytes,
        initialOlderDays: olderDays,
      ),
    ).then((_) {
      if (mounted) _refreshUsage();
    });
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final dark = settingsIsDark(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.s3, AppTokens.s5, AppTokens.s3, AppTokens.s3),
      child: Text(title,
          style: TextStyle(
            color: AppTokens.textPrimary(dark: dark),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final primary = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final total = _mediaBytes + _cacheBytes;
    final mediaFlex = total <= 0 ? 0 : (_mediaBytes * 100 ~/ total);

    return SettingsScaffold(
      title: settingsText(context, zh: '清理存储空间', en: 'Manage Storage'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _refreshUsage,
          tooltip: settingsText(context, zh: '刷新', en: 'Refresh'),
          icon: const Icon(Icons.refresh_rounded),
          color: AppTokens.accent,
        ),
      ],
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: AppTokens.s4),
          padding: const EdgeInsets.all(AppTokens.s6),
          decoration: BoxDecoration(
            color: AppTokens.surface(dark: dark),
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  settingsText(context,
                      zh: '可管理的本机文件', en: 'Manageable local files'),
                  style: TextStyle(color: secondary, fontSize: 13)),
              const SizedBox(height: AppTokens.s2),
              Row(children: [
                Text(
                  _loading
                      ? '…'
                      : _loadError
                          ? settingsText(context, zh: '统计失败', en: 'Unavailable')
                          : storageFormatBytes(total),
                  style: TextStyle(
                    color: primary,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(width: AppTokens.s4),
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ]),
              const SizedBox(height: AppTokens.s2),
              Text(
                settingsText(context,
                    zh: '本机聊天媒体与临时缓存',
                    en: 'Local chat media and temporary cache'),
                style: TextStyle(color: secondary, fontSize: 12),
              ),
              const SizedBox(height: AppTokens.s5),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.rPill),
                child: Row(children: [
                  if (_mediaBytes > 0)
                    Expanded(
                      flex: mediaFlex.clamp(1, 100),
                      child: Container(height: 11, color: AppTokens.accent),
                    ),
                  if (_cacheBytes > 0 || total == 0)
                    Expanded(
                      flex: total == 0 ? 100 : (100 - mediaFlex).clamp(1, 100),
                      child: Container(
                          height: 11,
                          color: dark
                              ? AppTokens.decorativeSparkle
                              : AppTokens.borderLight),
                    ),
                ]),
              ),
              const SizedBox(height: AppTokens.s4),
              Wrap(
                spacing: AppTokens.s5,
                runSpacing: AppTokens.s2,
                children: [
                  _legend(
                      context,
                      AppTokens.accent,
                      settingsText(context,
                          zh: '聊天媒体 ${storageFormatBytes(_mediaBytes)}',
                          en: 'Chat media ${storageFormatBytes(_mediaBytes)}')),
                  _legend(
                      context,
                      dark
                          ? AppTokens.decorativeSparkle
                          : AppTokens.borderLight,
                      settingsText(context,
                          zh: '缓存 ${storageFormatBytes(_cacheBytes)}',
                          en: 'Cache ${storageFormatBytes(_cacheBytes)}')),
                ],
              ),
            ],
          ),
        ),
        SettingsGroup(
          children: [
            SettingsCell(
              title: settingsText(context, zh: '缓存', en: 'Cache'),
              subtitle: settingsText(context,
                  zh: '图片缩略图、临时文件等\n不会删除聊天记录，可放心清理',
                  en: 'Thumbnails and temporary files\nChat messages will remain'),
              trailing: SizedBox(
                height: 64,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _loading
                          ? settingsText(context, zh: '统计中', en: 'Calculating')
                          : storageFormatBytes(_cacheBytes),
                      style: TextStyle(
                          color: settingsSecondaryTextColor(context),
                          fontSize: 14),
                    ),
                    const SizedBox(width: AppTokens.s3),
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: AppTokens.danger),
                      onPressed: _loading || _clearing || _cacheBytes == 0
                          ? null
                          : _clear,
                      child: Text(_clearing
                          ? settingsText(context, zh: '清理中', en: 'Clearing')
                          : settingsText(context, zh: '清理', en: 'Clear')),
                    ),
                  ],
                ),
              ),
              showArrow: false,
              showDivider: false,
            ),
          ],
        ),
        SettingsGroup(children: [
          SettingsCell(
            title: settingsText(context, zh: '聊天文件', en: 'Chat Files'),
            subtitle: settingsText(context,
                zh: '按聊天查看和清理本机图片、视频及文件',
                en: 'Review local photos, videos and files by chat'),
            value: _loading ? null : storageFormatBytes(_mediaBytes),
            onTap: _openChatFiles,
          ),
          SettingsCell(
            title: settingsText(context, zh: '已下载文件', en: 'Downloaded Files'),
            subtitle: settingsText(context,
                zh: '查看已缓存的聊天文件', en: 'View cached chat documents'),
            showDivider: false,
            onTap: () => _openChatFiles(type: StorageMediaType.file),
          ),
        ]),
        _sectionTitle(context,
            settingsText(context, zh: '推荐清理', en: 'Suggested cleanup')),
        SettingsGroup(children: [
          SettingsCell(
            title: settingsText(context, zh: '大文件', en: 'Large files'),
            subtitle: settingsText(context,
                zh: '查看超过 50 MB 的本机聊天文件',
                en: 'Find local chat files over 50 MB'),
            onTap: () => _openChatFiles(minBytes: 50 << 20),
          ),
          SettingsCell(
            title: settingsText(context, zh: '较早的文件', en: 'Older files'),
            subtitle: settingsText(context,
                zh: '查看 3 个月前的本机聊天文件',
                en: 'Find local chat files older than 3 months'),
            showDivider: false,
            onTap: () => _openChatFiles(olderDays: 90),
          ),
        ]),
      ],
    );
  }

  Widget _legend(BuildContext context, Color dotColor, String label) {
    final dark = settingsIsDark(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
      ),
      const SizedBox(width: AppTokens.s2),
      Text(label,
          style: TextStyle(
            color: AppTokens.textSecondary(dark: dark),
            fontSize: 12,
          )),
    ]);
  }
}

class _StorageUsage {
  const _StorageUsage({required this.mediaBytes, required this.cacheBytes});

  final int mediaBytes;
  final int cacheBytes;
}
