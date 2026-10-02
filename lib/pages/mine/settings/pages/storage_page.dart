import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path_provider/path_provider.dart';

import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

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
    setState(() => _loading = true);
    try {
      final usage = await _collectUsage();
      if (!mounted) return;
      setState(() {
        _mediaBytes = usage.mediaBytes;
        _cacheBytes = usage.cacheBytes;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<_StorageUsage> _collectUsage() async {
    final appCache = await getApplicationCacheDirectory();
    final temp = await getTemporaryDirectory();
    final mediaRoots = <Directory>[
      Directory('${appCache.path}${Platform.pathSeparator}picture'),
      Directory('${appCache.path}${Platform.pathSeparator}video'),
      Directory('${Config.cachePath}outgoing_media'),
    ];

    var media = 0;
    for (final dir in mediaRoots) {
      media += await _directorySize(dir);
    }

    var cache = await _directorySizeExcluding(
      appCache,
      excludedTopLevelNames: const {'picture', 'video'},
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
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
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
    final ok = await showSettingsConfirm(
      context,
      title: settingsText(context, zh: '清理缓存', en: 'Clear Cache'),
      message: settingsText(
        context,
        zh: '将清理本地缓存文件，但不会删除账号信息。是否继续？',
        en: 'Local cache will be cleared without removing account data. Continue?',
      ),
      confirmText: settingsText(context, zh: '清理', en: 'Clear'),
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _clearing = true);
    try {
      await _clearLocalCacheTargets();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _refreshUsage();
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context, zh: '缓存已清理', en: 'Cache cleared'),
      );
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
      excludedTopLevelNames: const {'picture', 'video'},
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    final digits = value >= 100 || index == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[index]}';
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final primary = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final border = AppTokens.border(dark: dark);
    final total = _mediaBytes + _cacheBytes;

    return SettingsScaffold(
      title: settingsText(context, zh: '储存空间', en: 'Storage'),
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTokens.surface(dark: dark),
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.storage_rounded,
                size: 36,
                color: AppTokens.accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settingsText(context, zh: '已用空间', en: 'Used Space'),
                      style: TextStyle(
                        color: primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _loading
                          ? settingsText(
                              context,
                              zh: '正在统计本地聊天图片、视频和缓存',
                              en: 'Calculating local chat media and cache usage...',
                            )
                          : _formatBytes(total),
                      style: TextStyle(color: secondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: _refreshUsage,
                  tooltip: settingsText(context, zh: '刷新', en: 'Refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppTokens.accent,
                ),
            ],
          ),
        ),
        SettingsGroup(
          children: [
            SettingsCell(
              title: settingsText(context, zh: '聊天图片和视频', en: 'Chat Photos and Videos'),
              value: _loading
                  ? settingsText(context, zh: '统计中', en: 'Calculating')
                  : _formatBytes(_mediaBytes),
              showArrow: false,
            ),
            SettingsCell(
              title: settingsText(context, zh: '缓存数据', en: 'Cached Data'),
              value: _loading
                  ? settingsText(context, zh: '统计中', en: 'Calculating')
                  : _formatBytes(_cacheBytes),
              showArrow: false,
              showDivider: false,
            ),
          ],
        ),
      ],
      bottom: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: (_loading || _clearing || _cacheBytes == 0) ? null : _clear,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: border,
                disabledForegroundColor: secondary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _clearing
                  ? Text(settingsText(context, zh: '清理中...', en: 'Clearing...'))
                  : Text(
                      settingsText(context, zh: '清理缓存', en: 'Clear Cache'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StorageUsage {
  const _StorageUsage({required this.mediaBytes, required this.cacheBytes});

  final int mediaBytes;
  final int cacheBytes;
}
