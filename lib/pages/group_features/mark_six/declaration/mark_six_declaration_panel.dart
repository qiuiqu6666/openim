// Adapted from 99chat settings/lottery_dashboard.dart (Apache-2.0).
// Source: https://github.com/qiuiqu6666/99chat.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/mark_six_repository.dart';
import '../widgets/mark_six_latest_card.dart' show markSixAssetPath;
import '../widgets/mark_six_style.dart';

class MarkSixDeclarationPanel extends StatefulWidget {
  const MarkSixDeclarationPanel({super.key, required this.repository});
  final MarkSixRepository repository;
  @override
  State<MarkSixDeclarationPanel> createState() =>
      _MarkSixDeclarationPanelState();
}

class _MarkSixDeclarationPanelState extends State<MarkSixDeclarationPanel> {
  String _downloadURL = '';
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || !widget.repository.current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.read('/chat/platform');
      if (!mounted || !widget.repository.current) return;
      setState(() => _downloadURL =
          '${data['downloadURL'] ?? data['officialURL'] ?? ''}'.trim());
    } catch (error) {
      if (mounted && widget.repository.current) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && widget.repository.current) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _copyDownloadURL() async {
    if (!widget.repository.current) return;
    if (_downloadURL.isEmpty) {
      await _load();
      return;
    }
    await Clipboard.setData(ClipboardData(text: _downloadURL));
    if (mounted && widget.repository.current) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('下载链接已复制')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    return DefaultTextStyle.merge(
        style: TextStyle(color: style.declarationText),
        child: Column(children: [
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: style.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: MarkSixStyle.declarationShadow,
                  border: Border.all(color: style.declarationBorder)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Image.asset(
                          '${markSixAssetPath}declaration_megaphone.png',
                          key:
                              const ValueKey('lottery-declaration-header-icon'),
                          excludeFromSemantics: true,
                          width: 32,
                          height: 32),
                      const SizedBox(width: 8),
                      const Text('本群宣言',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text('真实 · 公平 · 安全 · 稳定',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: style.declarationMuted))),
                    ]),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: style.declarationDivider),
                    const SizedBox(height: 10),
                    Container(
                        key: const ValueKey('lottery-declaration-quote'),
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(15, 14, 15, 22),
                        decoration: BoxDecoration(
                            color: style.declarationAlt,
                            borderRadius: BorderRadius.circular(12)),
                        child: Stack(children: [
                          Positioned(
                              right: 0,
                              bottom: -38,
                              child: ExcludeSemantics(
                                  child: IgnorePointer(
                                      child: Text('”',
                                          style: TextStyle(
                                              color: style.declarationQuote,
                                              fontSize: 86,
                                              fontWeight: FontWeight.w800))))),
                          const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '全天候直播开奖(用户实时亲眼所见)！\n'
                                    '公平骰子！公开发包！无任何套路！\n'
                                    '杜绝一切不透明开奖！\n'
                                    '上下分不卡分！快速！红包不回收！\n'
                                    '全部是真实用户在亲身参与点包！',
                                    style:
                                        TextStyle(fontSize: 14, height: 1.55)),
                                SizedBox(height: 16),
                                Text('十一年口碑！诚信经营！安全稳定！',
                                    style:
                                        TextStyle(fontSize: 14, height: 1.55)),
                              ]),
                        ])),
                    const SizedBox(height: 14),
                    Material(
                        color: style.declarationAlt,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                            key: const ValueKey('lottery-app-download-link'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: _loading ? null : _copyDownloadURL,
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(children: [
                                  Icon(Icons.download_rounded,
                                      color: style.primary, size: 23),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text('下载 App',
                                            style: TextStyle(
                                                color: style.declarationText,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 3),
                                        Text(
                                            _loading
                                                ? '正在获取下载链接…'
                                                : _error ??
                                                    (_downloadURL.isEmpty
                                                        ? '暂无下载链接，点击重试'
                                                        : _downloadURL),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: _downloadURL.isEmpty
                                                    ? style.declarationMuted
                                                    : style.primary)),
                                      ])),
                                  const SizedBox(width: 8),
                                  Icon(Icons.copy_rounded,
                                      size: 18,
                                      color: style.declarationCopyIcon),
                                ]))))
                  ])),
          const SizedBox(height: 22),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 22, height: 1, color: style.declarationRule),
            const SizedBox(width: 7),
            Flexible(
                child: Text('公平公开 · 真实可靠',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10, color: style.declarationFooter))),
            const SizedBox(width: 7),
            Container(width: 22, height: 1, color: style.declarationRule),
          ]),
        ]));
  }
}
