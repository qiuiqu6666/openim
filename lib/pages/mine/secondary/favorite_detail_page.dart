import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import '../../../services/favorite_send_coordinator.dart';
import '../../favorites/widgets/favorite_capability_gate.dart';
import '../../favorites/media/favorite_asset_preview.dart';
import '../../favorites/detail/favorite_detail_footer.dart';
import '../../favorites/detail/favorite_detail_metadata.dart';
import '../../favorites/detail/favorite_detail_tokens.dart';
import '../../favorites/favorite_p0.dart';
import '../settings/settings_navigation.dart';
import '../settings/widgets/settings_widgets.dart';
import 'favorite_note_edit_page.dart';
import 'favorites_page.dart'
    show
        favoriteKindIcon,
        favoriteKindLabel,
        favoriteStatusLabel,
        confirmCancelFavoriteSend;

class FavoriteDetailPage extends StatelessWidget {
  const FavoriteDetailPage(
      {super.key,
      required this.repository,
      required this.item,
      this.onSend,
      this.onCancelSend,
      this.readOnly = false});
  final FavoriteRepository repository;
  final FavoriteItem item;
  final Future<FavoriteSendResult> Function(FavoriteItem)? onSend;
  final Future<void> Function(FavoriteItem)? onCancelSend;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => FavoriteCapabilityGate(
      repository: repository,
      showScaffold: true,
      title: settingsText(context, zh: '收藏详情', en: 'Favorite details'),
      child: _FavoriteDetailContent(
          repository: repository,
          item: item,
          onSend: onSend,
          onCancelSend: onCancelSend,
          readOnly: readOnly));
}

class _FavoriteDetailContent extends StatefulWidget {
  const _FavoriteDetailContent(
      {required this.repository,
      required this.item,
      this.onSend,
      this.onCancelSend,
      required this.readOnly});
  final FavoriteRepository repository;
  final FavoriteItem item;
  final Future<FavoriteSendResult> Function(FavoriteItem)? onSend;
  final Future<void> Function(FavoriteItem)? onCancelSend;
  final bool readOnly;
  @override
  State<_FavoriteDetailContent> createState() => _FavoriteDetailPageState();
}

class _FavoriteDetailPageState extends State<_FavoriteDetailContent> {
  late FavoriteItem _item;
  late final String _scope;
  bool _loading = true;
  bool _hasDetail = false;
  bool _busy = false;
  bool _invalid = false;
  String? _error;
  bool _pendingSend = false;
  int? _unconfirmedDeleteVersion;
  bool _confirmingDelete = false;
  FavoriteItem? _pendingSendItem;

  String _text(String zh, String en) => settingsText(context, zh: zh, en: en);
  bool get _current => !_invalid && widget.repository.isSessionCurrent(_scope);
  bool get _canEditNote =>
      _item.kind == FavoriteKind.note &&
      _item.blocks.every((block) => block.type == 'text');

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_checkSession);
    unawaited(_load());
  }

  void _checkSession() {
    if (!_current && mounted && !_invalid) setState(() => _invalid = true);
  }

  Future<void> _load() async {
    if (!_current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await widget.repository.getDetail(_item.id);
      if (mounted && _current) {
        setState(() {
          _item = item;
          _hasDetail = true;
          if (_unconfirmedDeleteVersion != item.version) {
            _unconfirmedDeleteVersion = null;
          }
        });
      }
    } catch (error) {
      if (mounted && _current) {
        setState(() => _error = settingsErrorMessage(context, error,
            fallback:
                _text('详情加载失败，请重试', 'Could not load details. Please retry.')));
      }
    } finally {
      if (mounted && _current) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    if (_busy || !_current || !_canEditNote) return;
    final itemID = _item.id;
    var expectedVersion = _item.version;
    var title = _item.title;
    int? reviewedVersion;
    await openSettingsPage<String>(
        context,
        FavoriteNoteEditPage(
          repository: widget.repository,
          initialText: _item.text,
          onReviewConflict: (conflict) async {
            if (!_current) throw StateError('登录状态已改变');
            final snapshot = conflict.currentItem;
            final latest = snapshot == null || snapshot.content == null
                ? await widget.repository.getDetail(itemID)
                : snapshot;
            if (!_current || latest.id != itemID) {
              throw StateError('登录或收藏状态已改变');
            }
            return latest;
          },
          onAcceptConflict: (latest) {
            if (!_current ||
                latest.id != itemID ||
                latest.kind != FavoriteKind.note ||
                latest.content == null ||
                latest.blocks.any((block) => block.type != 'text')) {
              throw StateError('该收藏不支持纯文字编辑');
            }
            expectedVersion = latest.version;
            title = latest.title;
            reviewedVersion = latest.version;
          },
          onSave: (text) async {
            if (!_current) throw StateError('登录状态已改变');
            await widget.repository.updateNote(itemID, text,
                expectedVersion: expectedVersion, title: title);
            if (_current && reviewedVersion != null) {
              await widget.repository.resolveConflictingEdits(itemID,
                  throughVersion: reviewedVersion! - 1);
            }
          },
        ));
    if (mounted && _current) await _load();
  }

  Future<void> _retryArchive() async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final item = await widget.repository.retryArchive(_item.id);
      if (mounted && _current) setState(() => _item = item);
    } catch (error) {
      if (mounted && _current) {
        setState(() => _error = error is FavoriteApiException
            ? error.message
            : _text('保存重试失败，请重试', 'Could not retry saving. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || !_current) return;
    setState(() => _busy = true);
    var submitted = false;
    try {
      if (_unconfirmedDeleteVersion != null) {
        final latest = await widget.repository.getDetail(_item.id);
        if (!mounted || !_current) return;
        if (latest.id != _item.id ||
            latest.version == _unconfirmedDeleteVersion) {
          throw const FavoriteApiException(20061, '最新版本尚未核实，请刷新后重试');
        }
        setState(() {
          _item = latest;
          _hasDetail = latest.content != null;
          _unconfirmedDeleteVersion = null;
        });
      }
      setState(() => _confirmingDelete = true);
      final confirmed = await showSettingsConfirm(context,
          title: _text('删除收藏', 'Delete favorite'),
          message: _text('删除后无法恢复。已发送的聊天消息会保留。',
              'This cannot be undone. Messages already sent will be kept.'),
          confirmText: _text('删除', 'Delete'),
          destructive: true);
      if (!mounted || !confirmed || !_current) return;
      setState(() => _confirmingDelete = false);
      submitted = true;
      await widget.repository.delete(_item.id, expectedVersion: _item.version);
      if (mounted && _current) Navigator.of(context).pop();
    } catch (error) {
      if (mounted && _current) {
        if (submitted &&
            error is FavoriteApiException &&
            error.isVersionConflict) {
          final rejectedVersion = _item.version;
          _unconfirmedDeleteVersion = rejectedVersion;
          FavoriteItem? latest = error.currentItem;
          if (latest == null) {
            try {
              latest = await widget.repository.getDetail(_item.id);
            } catch (_) {/* A later confirmation needs a successful re-read. */}
          }
          if (mounted &&
              _current &&
              latest?.id == _item.id &&
              latest!.version != rejectedVersion) {
            final confirmedLatest = latest;
            setState(() {
              _item = confirmedLatest;
              _hasDetail = _item.content != null;
              _unconfirmedDeleteVersion = null;
            });
          }
        }
        if (!mounted || !_current) return;
        showSettingsError(context, error,
            _text('删除失败，请重试', 'Could not delete. Please retry.'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmingDelete = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (_busy ||
        !_current ||
        !canSendFavoriteP0(_item) ||
        widget.onSend == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sendingItem = _pendingSendItem ?? _item;
      await widget.repository.requireAvailable();
      if (!mounted || !_current) return;
      final result = await widget.onSend!(sendingItem);
      if (!mounted || !_current || result.errorCode == 'CANCELLED') return;
      if (result.errorCode == 'BATCH_RESELECT_REQUIRED') {
        await _load();
        if (mounted && _current) {
          setState(() {
            _pendingSend = false;
            _pendingSendItem = null;
            _error = result.errorMessage ??
                _text('收藏内容已更新，请检查最新详情再选择发送目标',
                    'This favorite has changed. Check the updated details and select a destination again.');
          });
        }
        return;
      }
      if (result.status == FavoriteSendStatus.success) {
        setState(() {
          _pendingSend = false;
          _pendingSendItem = null;
        });
        showSettingsMessage(context, _text('已发送', 'Sent'));
      } else {
        _pendingSend = true;
        _pendingSendItem = sendingItem;
        setState(() => _error = result.status == FavoriteSendStatus.unknown
            ? _text('发送状态待确认，请先查看目标对话',
                'Sending status is unconfirmed. Check the destination chat first.')
            : result.errorMessage ??
                _text('发送失败，请重试', 'Could not send. Please retry.'));
      }
    } catch (error) {
      if (mounted && _current) {
        setState(() => _error = settingsErrorMessage(context, error,
            fallback: _text('发送失败，请重试', 'Could not send. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelSend() async {
    if (_busy || !_current || !_pendingSend || widget.onCancelSend == null) {
      return;
    }
    final confirmed = await confirmCancelFavoriteSend(context);
    if (!mounted || !_current || !confirmed) return;
    setState(() => _busy = true);
    try {
      await widget.onCancelSend!(_pendingSendItem ?? _item);
      if (mounted && _current) {
        setState(() {
          _pendingSend = false;
          _pendingSendItem = null;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && _current) {
        setState(() => _error = error is FavoriteApiException
            ? error.message
            : _text('取消失败，请重试', 'Could not cancel. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_checkSession);
    super.dispose();
  }

  Widget _assetContent(FavoriteAsset asset, FavoriteKind kind) {
    if (asset.role == 'original' && asset.mimeType.startsWith('audio/')) {
      return FavoriteAssetPreview(
          key: ValueKey('${_item.id}:${asset.id}:${_item.version}'),
          repository: widget.repository,
          item: _item,
          asset: asset);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (asset.role == 'original' &&
          (asset.mimeType.startsWith('image/') ||
              asset.mimeType.startsWith('video/') ||
              asset.mimeType.startsWith('audio/')))
        FavoriteAssetPreview(
            key: ValueKey('${_item.id}:${asset.id}:${_item.version}'),
            repository: widget.repository,
            item: _item,
            asset: asset),
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(favoriteKindIcon(kind), color: AppTokens.accent),
          title: Text(asset.fileName?.trim().isNotEmpty == true
              ? asset.fileName!
              : favoriteKindLabel(context, kind)),
          subtitle: Text(
              '${(asset.sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB'
              '${asset.durationMs == null ? '' : ' · ${(asset.durationMs! / 1000).ceil()}s'}')),
    ]);
  }

  Widget _blockContent(FavoriteBlock block, [int depth = 0]) {
    if (block.type == 'message' && depth <= 2) {
      final nested = block.data['blocks'] ??
          (block.data['content'] is Map
              ? (block.data['content'] as Map)['blocks']
              : null);
      final name = block.data['senderName'] ?? block.data['displayName'];
      if (nested is List && nested.length <= 100) {
        try {
          final children = nested
              .map((raw) =>
                  FavoriteBlock.fromJson(Map<String, dynamic>.from(raw as Map)))
              .toList();
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (name is String && name.isNotEmpty)
                  Text(name,
                      style: TextStyle(
                          color: settingsSecondaryTextColor(context))),
                for (final child in children)
                  Padding(
                      padding: const EdgeInsets.only(top: AppTokens.s4),
                      child: _blockContent(child, depth + 1)),
              ]);
        } catch (_) {/* Unknown content stays visible without executing it. */}
      }
    } else if (block.type == 'text') {
      return SelectableText(block.text ?? '',
          style: TextStyle(
              color: settingsTextColor(context),
              fontSize: AppTokens.listTitleFontSize,
              height: 1.5));
    } else if (block.type == 'link') {
      final url = block.data['url'];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (block.text?.isNotEmpty == true) SelectableText(block.text!),
        if (url is String)
          SelectableText(url, style: const TextStyle(color: AppTokens.accent)),
      ]);
    } else if (block.type == 'location' || block.type == 'contact') {
      return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
              block.type == 'location'
                  ? Icons.location_on_outlined
                  : Icons.person_outline,
              color: AppTokens.accent),
          title: SelectableText([
            for (final key in block.type == 'location'
                ? ['title', 'description', 'address', 'latitude', 'longitude']
                : ['nickname', 'userID'])
              if (block.data[key] is String || block.data[key] is num)
                '${block.data[key]}',
          ].join('\n')));
    } else if (['image', 'video', 'audio', 'file'].contains(block.type)) {
      final asset = _item.assets
          .where(
              (asset) => asset.id == block.assetID && asset.role == 'original')
          .firstOrNull;
      if (asset != null) {
        return _assetContent(asset, FavoriteKind.parse(block.type));
      }
      return Text(_text('附件原件暂不可用，请刷新详情',
          'The original attachment is unavailable. Refresh details.'));
    }
    return Text(_text('此内容暂无法预览，请更新客户端',
        'This content cannot be previewed yet. Update the app.'));
  }

  Widget _content() {
    if (!_item.isSupported) {
      return SettingsEmptyState(
          icon: Icons.help_outline,
          title: _text(
              '此版本暂不支持此收藏', 'This version does not support this favorite'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_item.blocks.isEmpty && _item.text.trim().isNotEmpty)
        SelectableText(_item.text,
            style: TextStyle(
                color: settingsTextColor(context),
                fontSize: AppTokens.listTitleFontSize,
                height: 1.5)),
      for (var index = 0; index < _item.blocks.length; index++)
        Padding(
            key: ValueKey('favorite-block-${_item.blocks[index].id}'),
            padding: EdgeInsets.only(top: index == 0 ? 0 : AppTokens.s5),
            child: _blockContent(_item.blocks[index])),
      if (_item.blocks.isEmpty)
        for (final asset
            in _item.assets.where((asset) => asset.role == 'original'))
          _assetContent(asset, _item.kind),
      if (!canSendFavoriteP0(_item) ||
          favoriteStatusLabel(context, _item).isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: AppTokens.s5),
            child: Text(favoriteStatusLabel(context, _item).isEmpty
                ? _text('此内容暂不能快捷发送', 'This content cannot be sent yet')
                : favoriteStatusLabel(context, _item))),
    ]);
  }

  Widget? _actions() {
    final canShowSend =
        widget.onSend != null && favoriteP0Kinds.contains(_item.kind);
    final canShowEdit = !widget.readOnly &&
        (_item.status == FavoriteStatus.failed || _canEditNote);
    final canShowCancel =
        !widget.readOnly && _pendingSend && widget.onCancelSend != null;
    if (!canShowSend && !canShowEdit && !canShowCancel) return null;
    return FavoriteDetailFooter(
      pendingAction:
          !widget.readOnly && _pendingSend && widget.onCancelSend != null
              ? TextButton.icon(
                  key: const ValueKey('favorite-detail-cancel-send'),
                  onPressed: _busy ? null : _cancelSend,
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(_text('取消剩余发送', 'Cancel remaining sends')))
              : null,
      actions: [
        if (!widget.readOnly && _item.status == FavoriteStatus.failed)
          OutlinedButton.icon(
              key: const ValueKey('favorite-detail-retry-archive'),
              onPressed: _busy || _loading ? null : _retryArchive,
              icon: const Icon(Icons.refresh),
              label: Text(_text('重试保存', 'Retry saving'))),
        if (!widget.readOnly &&
            _canEditNote &&
            _item.status != FavoriteStatus.failed)
          OutlinedButton.icon(
              key: const ValueKey('favorite-detail-edit'),
              onPressed: _busy || _loading ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: Text(_text('编辑', 'Edit'))),
        if (widget.onSend != null && favoriteP0Kinds.contains(_item.kind))
          FilledButton.icon(
              key: const ValueKey('favorite-detail-send'),
              onPressed:
                  _busy || _loading || !_hasDetail || !canSendFavoriteP0(_item)
                      ? null
                      : _send,
              icon: const Icon(CupertinoIcons.paperplane),
              label: Text(_text('发送到对话', 'Send to a chat'))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Scaffold(
      backgroundColor: AppTokens.background(dark: dark),
      appBar: GlassAppBar(
          centerTitle: true,
          leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              color: AppTokens.accent,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(CupertinoIcons.chevron_back)),
          title: Text(_text('收藏详情', 'Favorite details'),
              style: TextStyle(
                  fontSize: AppTokens.listTitleFontSize,
                  fontWeight: FontWeight.w600,
                  color: settingsTextColor(context))),
          actions: [
            if (!widget.readOnly && !_invalid)
              IconButton(
                  tooltip: _text('删除收藏', 'Delete favorite'),
                  onPressed: _busy || _loading ? null : _delete,
                  color: settingsSecondaryTextColor(context),
                  icon: const Icon(Icons.delete_outline)),
          ]),
      bottomNavigationBar: _invalid ? null : _actions(),
      body: SafeArea(
          top: false,
          child: _invalid
              ? SettingsEmptyState(
                  icon: Icons.lock_outline,
                  title: _text('登录状态已改变，请重新打开收藏',
                      'Your account changed. Reopen favorites.'))
              : Column(children: [
                  if (_loading || (_busy && !_confirmingDelete))
                    const LinearProgressIndicator(),
                  Expanded(
                      child: Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth:
                                      FavoriteDetailTokens.contentMaxWidth),
                              child: ListView(
                                  padding: const EdgeInsets.all(AppTokens.s5),
                                  children: [
                                    if (_error != null)
                                      Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: AppTokens.s5),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Semantics(
                                                    liveRegion: true,
                                                    child: Text(_error!,
                                                        style: TextStyle(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .error))),
                                                TextButton(
                                                    onPressed:
                                                        _busy ? null : _load,
                                                    child: Text(_text('刷新详情',
                                                        'Refresh details'))),
                                              ])),
                                    Container(
                                        key: const ValueKey(
                                            'favorite-detail-content'),
                                        padding: const EdgeInsets.all(
                                            FavoriteDetailTokens
                                                .contentPadding),
                                        decoration: BoxDecoration(
                                            color:
                                                AppTokens.surface(dark: dark),
                                            borderRadius: BorderRadius.circular(
                                                AppTokens.rLg)),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (_item.title.isNotEmpty) ...[
                                                Text(_item.title,
                                                    style: TextStyle(
                                                        fontSize: AppTokens
                                                            .listTitleFontSize,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            settingsTextColor(
                                                                context))),
                                                const SizedBox(
                                                    height: AppTokens.s5),
                                              ],
                                              if (_loading)
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            AppTokens.s6),
                                                    child: Center(
                                                        child: LoadingView
                                                            .indicator(
                                                                size: AppTokens
                                                                    .s7,
                                                                style:
                                                                    LoadingIndicatorStyle
                                                                        .ring)))
                                              else
                                                _content(),
                                            ])),
                                    FavoriteDetailMetadata(item: _item),
                                  ])))),
                ])),
    );
  }
}
