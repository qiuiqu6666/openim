import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../widgets/wallet_99chat_tokens.dart';
import 'wallet_i18n.dart';

class WalletQrScannerPage extends StatefulWidget {
  const WalletQrScannerPage({super.key});

  @override
  State<WalletQrScannerPage> createState() => _WalletQrScannerPageState();
}

class _WalletQrScannerPageState extends State<WalletQrScannerPage> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'wallet-qr-reader');
  QRViewController? _controller;
  StreamSubscription<Barcode>? _subscription;
  bool _handled = false;

  void _onCreated(QRViewController controller) {
    _controller = controller;
    _subscription = controller.scannedDataStream.listen((barcode) {
      if (_handled) return;
      final code = barcode.code?.trim() ?? '';
      if (code.isEmpty) return;
      _handled = true;
      _controller?.pauseCamera();
      if (mounted) Navigator.of(context).pop(code);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          i18n.t(
            zhHans: '扫一扫',
            zhHant: '掃一掃',
            en: 'Scan',
            ja: 'スキャン',
            ko: '스캔',
          ),
        ),
      ),
      body: QRView(
        key: _qrKey,
        onQRViewCreated: _onCreated,
        overlay: QrScannerOverlayShape(
          borderColor: AppTokens.accent,
          borderRadius: 18,
          borderLength: 34,
          borderWidth: 6,
          cutOutSize: MediaQuery.sizeOf(context).width * .68,
        ),
      ),
    );
  }
}
