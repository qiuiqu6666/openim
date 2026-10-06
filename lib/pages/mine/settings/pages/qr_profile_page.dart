import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:openim/pages/contacts/scanning/friend_qr_scanner.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/settings_widgets.dart';

class QrProfilePage extends StatefulWidget {
  const QrProfilePage({
    super.key,
    required this.nickname,
    required this.userId,
    required this.avatarUrl,
    this.account = '',
    this.avatarBytes,
    this.inviteFactory,
  });

  final String nickname;
  /// SDK identity used in the invitation protocol.
  final String userId;
  /// Public 99Chat account displayed on the QR card.
  final String account;
  final String avatarUrl;
  final Uint8List? avatarBytes;
  final Future<String> Function(FriendAddSource)? inviteFactory;

  @override
  State<QrProfilePage> createState() => _QrProfilePageState();
}

class _QrProfilePageState extends State<QrProfilePage> {
  static const MethodChannel _systemShareChannel =
      MethodChannel('openim_system_share');

  final GlobalKey _captureKey = GlobalKey();
  bool _saving = false;
  String? _qrInvite;
  String? _linkInvite;
  String? _inviteError;

  @override
  void initState() {
    super.initState();
    _loadInvite();
  }

  Future<void> _loadInvite() async {
    try {
      final code = await (widget.inviteFactory ??
          Apis.createFriendInvite)(FriendAddSource.qrcode);
      if (mounted) setState(() => _qrInvite = code);
    } catch (_) {
      if (mounted) setState(() => _inviteError = '二维码邀请暂不可用，点击重试');
    }
  }

  Future<bool> _ensureLink() async {
    try {
      _linkInvite ??= await (widget.inviteFactory ??
          Apis.createFriendInvite)(FriendAddSource.link);
      return mounted;
    } catch (error) {
      if (mounted)
        showSettingsMessage(
            context,
            friendAddErrorMessage(error,
                    chinese:
                        Localizations.localeOf(context).languageCode == 'zh') ??
                '邀请暂不可用，请稍后重试');
      return false;
    }
  }

  String _inviteUrl(String code, String source) => Uri(
      scheme: 'openim',
      host: 'user',
      path: '/${widget.userId.trim()}',
      queryParameters: {'inviteCode': code, 'source': source}).toString();

  String get _displayName {
    final nickname = widget.nickname.trim();
    if (nickname.isNotEmpty) return nickname;
    final account = widget.account.trim();
    return account.isEmpty ? '99Chat' : account;
  }

  String get _displayId =>
      widget.account.trim().isEmpty ? '--' : widget.account.trim();

  String get _qrData =>
      _qrInvite == null ? '' : _inviteUrl(_qrInvite!, 'qrcode');

  String get _shareText => settingsText(
        context,
        zh: '你好，我是$_displayName\n邀请你在 99Chat 添加我为好友，随时聊聊、分享日常。\n我的好友邀请：${_linkInvite == null ? '' : _inviteUrl(_linkInvite!, 'link')}',
        en: 'Hi, I’m $_displayName! Add me on 99Chat to stay in touch.\n${_linkInvite == null ? '' : _inviteUrl(_linkInvite!, 'link')}',
      );

  Widget _avatar(double size) {
    final bytes = widget.avatarBytes;
    if (bytes == null || bytes.isEmpty) {
      return ClipOval(
        child: AvatarView(
          url: widget.avatarUrl,
          text: _displayName,
          width: size,
          height: size,
        ),
      );
    }
    return ClipOval(
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _brandLogo(double size) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .2),
        child: Image.asset(
          'assets/img/99chat_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );

  Future<Uint8List?> _captureCard() async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveImage() async {
    if (_qrInvite == null) return;
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _captureCard();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          showSettingsMessage(
            context,
            settingsText(context, zh: '保存失败，请稍后重试', en: 'Unable to save image'),
          );
        }
        return;
      }
      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        quality: 100,
        name: '99chat_my_qr_${widget.userId.trim()}',
      );
      if (!mounted) return;
      showSettingsMessage(
        context,
        result != null
            ? settingsText(context, zh: '图片已保存', en: 'Image saved')
            : settingsText(context,
                zh: '保存失败，请稍后重试', en: 'Unable to save image'),
      );
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context,
            zh: '保存失败，请检查相册权限', en: 'Unable to save. Check photo permission.'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openScanner() async {
    final accountID = DataSp.userID;
    final sessionToken = DataSp.chatToken;
    final invite = await scanFriendQrCode(context, onMyQrTap: () async {
      if (mounted) Navigator.of(context).pop();
    });
    if (!mounted ||
        invite == null ||
        DataSp.userID != accountID ||
        DataSp.chatToken != sessionToken) {
      return;
    }
    AppNavigator.startUserProfilePane(
      userID: invite['userID']!,
      addSource: invite['source'] == 'link'
          ? FriendAddSource.link
          : FriendAddSource.qrcode,
      friendAddFields: {'inviteCode': invite['inviteCode']!},
      forceCanAdd: true,
    );
  }

  Future<void> _copyInvitation() async {
    if (!await _ensureLink()) return;
    await Clipboard.setData(ClipboardData(text: _shareText));
    if (!mounted) return;
    showSettingsMessage(
      context,
      settingsText(context, zh: '邀请链接已复制', en: 'Invitation copied'),
    );
  }

  Future<void> _shareToApp(String scheme, String label) async {
    if (!await _ensureLink()) return;
    await Clipboard.setData(ClipboardData(text: _shareText));
    try {
      final uri = Uri.parse(scheme);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    if (!mounted) return;
    showSettingsMessage(
      context,
      settingsText(
        context,
        zh: '邀请链接已复制，请在$label中粘贴发送',
        en: 'Invitation copied. Paste it into $label.',
      ),
    );
  }

  Future<void> _systemShare() async {
    if (!await _ensureLink()) return;
    try {
      final handled = await _systemShareChannel.invokeMethod<bool>(
        'shareText',
        {'text': _shareText},
      );
      if (handled == true) return;
    } on MissingPluginException {
      // Non-Android platforms fall back to share_plus below.
    } on PlatformException {
      // Native chooser unavailable: use the cross-platform fallback.
    }
    await Share.share(_shareText);
  }

  void _showActions() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(settingsText(context, zh: '二维码', en: 'QR Code')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _saveImage();
            },
            child: Text(settingsText(context, zh: '保存图片', en: 'Save image')),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _openScanner();
            },
            child: Text(settingsText(context, zh: '扫一扫', en: 'Scan')),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _systemShare();
            },
            child: Text(settingsText(context, zh: '分享好友', en: 'Share')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(settingsText(context, zh: '取消', en: 'Cancel')),
        ),
      ),
    );
  }

  Widget _qrFrame(_QrPalette palette, double qrSize) {
    const framePadding = 14.0;
    final frameSize = qrSize + framePadding * 2;
    final logoSize = (qrSize * .18).clamp(34.0, 44.0).toDouble();
    return SizedBox.square(
      dimension: frameSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.primary
                      .withValues(alpha: palette.dark ? .35 : .22),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary
                        .withValues(alpha: palette.dark ? .20 : .12),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
                painter: _QrCornerFramePainter(color: palette.primary)),
          ),
          if (_qrInvite == null)
            SizedBox(
                width: qrSize,
                height: qrSize,
                child: Center(
                    child: TextButton(
                        onPressed: _loadInvite,
                        child: Text(_inviteError ?? '正在生成邀请二维码'))))
          else
            QrImageView(
              data: _qrData,
              version: QrVersions.auto,
              size: qrSize,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          Container(
            width: logoSize,
            height: logoSize,
            padding: EdgeInsets.all(logoSize * .08),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(logoSize * .18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .06),
                  blurRadius: 4,
                ),
              ],
            ),
            child: _brandLogo(logoSize * .84),
          ),
        ],
      ),
    );
  }

  Widget _shareCard(_QrPalette palette, double maxWidth) {
    final cardWidth = maxWidth.clamp(280.0, 360.0).toDouble();
    final qrSize = (cardWidth * .56).clamp(188.0, 216.0).toDouble();
    return Center(
      child: SizedBox(
        width: cardWidth,
        child: RepaintBoundary(
          key: _captureKey,
          child: Container(
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  top: 18,
                  right: 18,
                  child: CustomPaint(
                    size: const Size(56, 40),
                    painter: _DotGridPainter(color: palette.dot),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 60,
                  child: CustomPaint(
                      painter: _CardWavePainter(color: palette.primary)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _avatar(62),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '99号ID: $_displayId',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.secondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _qrFrame(palette, qrSize),
                      const SizedBox(height: 8),
                      Text(
                        settingsText(
                          context,
                          zh: '扫描二维码添加我为联系人',
                          en: 'Scan the QR code to add me',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: palette.secondary,
                            fontSize: 13,
                            height: 1.35),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        settingsText(
                          context,
                          zh: '分享二维码，连接更多朋友',
                          en: 'Share your QR code and connect with more friends',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: palette.secondary,
                            fontSize: 12,
                            height: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Divider(color: palette.border, height: 12, thickness: .5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _brandLogo(28),
                          const SizedBox(width: 8),
                          Text(
                            '99Chat',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shareActions(_QrPalette palette) {
    Widget actionItem({
      required double width,
      required String label,
      required VoidCallback onTap,
      String? asset,
      IconData? icon,
    }) {
      return SizedBox(
        width: width,
        child: Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (asset != null)
                    Image.asset(
                      asset,
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    )
                  else
                    Icon(icon, color: palette.primary, size: 28),
                  const SizedBox(height: 9),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.text, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey('qr-share-actions'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.card.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              MediaQuery.textScalerOf(context).scale(14) > 20 ? 2 : 4;
          const spacing = 14.0;
          final itemWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: 8,
            children: [
              actionItem(
                width: itemWidth,
                label: settingsText(context, zh: '分享微信', en: 'WeChat'),
                asset: 'assets/images/vx .png',
                onTap: () => _shareToApp('weixin://', '微信'),
              ),
              actionItem(
                width: itemWidth,
                label: settingsText(context, zh: '分享QQ', en: 'QQ'),
                asset: 'assets/images/qq.png',
                onTap: () => _shareToApp('mqq://', 'QQ'),
              ),
              actionItem(
                width: itemWidth,
                label: settingsText(context, zh: '复制链接', en: 'Copy link'),
                icon: Icons.link_rounded,
                onTap: _copyInvitation,
              ),
              actionItem(
                width: itemWidth,
                label: settingsText(context, zh: '更多分享', en: 'More'),
                icon: Icons.more_horiz_rounded,
                onTap: _systemShare,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bottomActions(_QrPalette palette) {
    Widget item({
      required IconData icon,
      required String label,
      required bool filled,
      required VoidCallback? onTap,
      required Key key,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(28),
            child: Ink(
              height: 52,
              decoration: BoxDecoration(
                color: filled ? palette.primary : palette.card,
                borderRadius: BorderRadius.circular(28),
                border: filled
                    ? null
                    : Border.all(color: palette.primary, width: 1.4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_saving && key == const ValueKey('qr-save'))
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: filled ? Colors.white : palette.primary,
                      ),
                    )
                  else
                    Icon(icon,
                        size: 20,
                        color: filled ? Colors.white : palette.primary),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: filled ? Colors.white : palette.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      key: const ValueKey('qr-bottom-actions'),
      children: [
        item(
          key: const ValueKey('qr-save'),
          icon: Icons.download_rounded,
          label: settingsText(context, zh: '保存图片', en: 'Save image'),
          filled: false,
          onTap: _saving ? null : _saveImage,
        ),
        const SizedBox(width: 14),
        item(
          key: const ValueKey('qr-scan'),
          icon: Icons.qr_code_scanner_rounded,
          label: settingsText(context, zh: '扫一扫', en: 'Scan'),
          filled: true,
          onTap: _openScanner,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final palette = _QrPalette.resolve(dark);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: palette.top,
      appBar: GlassAppBar(
        toolbarHeight: kToolbarHeight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: AppSystemBars.styleFor(palette.top,
            navigationBackground: palette.bottom),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: palette.primary,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          settingsText(context, zh: '我的二维码', en: 'My QR Code'),
          style: TextStyle(
              color: palette.text, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            key: const ValueKey('qr-more'),
            onPressed: _showActions,
            icon: Icon(Icons.more_horiz_rounded,
                color: palette.primary, size: 26),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/ivnbg.webp',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.top, palette.bottom],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth =
                    (constraints.maxWidth - 40).clamp(280.0, 420.0).toDouble();
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    MediaQuery.paddingOf(context).bottom + 20,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  settingsText(context,
                                      zh: '扫一扫，添加我为好友',
                                      en: 'Scan to add me as a friend'),
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  settingsText(context,
                                      zh: '一起交流 · 分享精彩 · 连接更多朋友',
                                      en: 'Chat · Share · Connect'),
                                  style: TextStyle(
                                      color: palette.secondary,
                                      fontSize: 14,
                                      height: 1.5),
                                ),
                              ],
                            ),
                          ),
                          _shareCard(palette, contentWidth),
                          const SizedBox(height: 14),
                          _shareActions(palette),
                          const SizedBox(height: 12),
                          _bottomActions(palette),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QrPalette {
  const _QrPalette({
    required this.dark,
    required this.primary,
    required this.top,
    required this.bottom,
    required this.card,
    required this.border,
    required this.shadow,
    required this.text,
    required this.secondary,
    required this.dot,
  });

  final bool dark;
  final Color primary;
  final Color top;
  final Color bottom;
  final Color card;
  final Color border;
  final Color shadow;
  final Color text;
  final Color secondary;
  final Color dot;

  factory _QrPalette.resolve(bool dark) {
    if (dark) {
      return _QrPalette(
        dark: true,
        primary: AppTokens.accent,
        top: const Color(0xFF122033),
        bottom: const Color(0xFF101A28),
        card: const Color(0xFF192331),
        border: const Color(0xFF334257),
        shadow: Colors.black.withValues(alpha: .35),
        text: const Color(0xFFF5F7FA),
        secondary: const Color(0xFFADB8CB),
        dot: const Color(0xFF4A5568),
      );
    }
    return _QrPalette(
      dark: false,
      primary: AppTokens.accent,
      top: const Color(0xFFD6EBFF),
      bottom: const Color(0xFFEEF6FF),
      card: Colors.white,
      border: const Color(0xFFD8E8FA),
      shadow: AppTokens.accent.withValues(alpha: .12),
      text: const Color(0xFF1A2332),
      secondary: const Color(0xFF8C97A8),
      dot: const Color(0xFFD0D5DC),
    );
  }
}

class _QrCornerFramePainter extends CustomPainter {
  const _QrCornerFramePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const inset = 6.0;
    final length = size.shortestSide * .16;
    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;
    final radius = (length * .4).clamp(0.0, 12.0);
    final path = Path()
      ..moveTo(left, top + length)
      ..lineTo(left, top + radius)
      ..arcToPoint(Offset(left + radius, top), radius: Radius.circular(radius))
      ..lineTo(left + length, top)
      ..moveTo(right - length, top)
      ..lineTo(right - radius, top)
      ..arcToPoint(Offset(right, top + radius), radius: Radius.circular(radius))
      ..lineTo(right, top + length)
      ..moveTo(right, bottom - length)
      ..lineTo(right, bottom - radius)
      ..arcToPoint(Offset(right - radius, bottom),
          radius: Radius.circular(radius))
      ..lineTo(right - length, bottom)
      ..moveTo(left + length, bottom)
      ..lineTo(left + radius, bottom)
      ..arcToPoint(Offset(left, bottom - radius),
          radius: Radius.circular(radius))
      ..lineTo(left, bottom - length);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_QrCornerFramePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .55);
    const spacing = 7.0;
    const radius = 1.1;
    for (var y = radius; y < size.height; y += spacing) {
      for (var x = radius; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => oldDelegate.color != color;
}

class _CardWavePainter extends CustomPainter {
  const _CardWavePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: .05),
          color.withValues(alpha: .09),
        ],
      ).createShader(Offset.zero & size);
    final path = Path()
      ..moveTo(0, size.height * .42)
      ..cubicTo(size.width * .22, size.height * .12, size.width * .42,
          size.height * .72, size.width * .62, size.height * .38)
      ..cubicTo(size.width * .78, size.height * .12, size.width * .9,
          size.height * .55, size.width, size.height * .28)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CardWavePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _QrBackdropPainter extends CustomPainter {
  const _QrBackdropPainter({required this.primary, required this.dark});
  final Color primary;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..color = primary.withValues(alpha: dark ? .10 : .08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42);
    final p2 = Paint()
      ..color = Colors.white.withValues(alpha: dark ? .03 : .45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);
    canvas.drawCircle(
        Offset(size.width * .1, size.height * .23), size.width * .26, p1);
    canvas.drawCircle(
        Offset(size.width * .95, size.height * .14), size.width * .34, p2);
    canvas.drawCircle(
        Offset(size.width * .82, size.height * .70), size.width * .28, p1);
  }

  @override
  bool shouldRepaint(_QrBackdropPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.dark != dark;
}
