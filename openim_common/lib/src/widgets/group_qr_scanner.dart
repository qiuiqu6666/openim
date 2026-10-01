import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:openim_common/openim_common.dart';
import '../utils/group_qr_link.dart';

class GroupQrScanner extends StatefulWidget {
  const GroupQrScanner({super.key});
  @override
  State<GroupQrScanner> createState() => _GroupQrScannerState();
}

class _GroupQrScannerState extends State<GroupQrScanner>
    with WidgetsBindingObserver {
  final _key = GlobalKey();
  QRViewController? _camera;
  StreamSubscription<Barcode>? _subscription;
  bool _returned = false;
  bool _denied = false;
  String? _invalid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_returned) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_setCameraActive(true));
    } else {
      unawaited(_setCameraActive(false));
    }
  }

  Future<void> _setCameraActive(bool active) async {
    try {
      if (active) {
        await _camera?.resumeCamera();
      } else {
        await _camera?.pauseCamera();
      }
    } catch (_) {
      // The native view may already be detached during navigation.
    }
  }

  void _created(QRViewController camera) {
    _camera = camera;
    _subscription?.cancel();
    _subscription = camera.scannedDataStream.listen((barcode) async {
      if (_returned || !mounted || barcode.code == null) return;
      final id = parseGroupQrLink(barcode.code!);
      if (id == null) {
        if (_invalid != barcode.code) {
          _invalid = barcode.code;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('groupQrInvalid'.tr)));
        }
        return;
      }
      _returned = true;
      await _setCameraActive(false);
      if (mounted) Navigator.pop(context, id);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _camera = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GlassAppBar(
            title: Text(StrRes.scan),
            centerTitle: true,
            leading: IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: Theme.of(context).colorScheme.primary))),
        body: Stack(children: [
          QRView(
              key: _key,
              onQRViewCreated: _created,
              formatsAllowed: const [BarcodeFormat.qrcode],
              onPermissionSet: (_, granted) {
                if (mounted) setState(() => _denied = !granted);
              },
              overlay: QrScannerOverlayShape(
                  borderColor: Theme.of(context).colorScheme.primary,
                  borderRadius: 16,
                  borderLength: 24,
                  borderWidth: 3,
                  cutOutSize: MediaQuery.sizeOf(context).shortestSide * .65)),
          if (_denied)
            Center(
                child: FilledButton(
                    onPressed: openAppSettings,
                    child: Text('groupQrCameraPermission'.tr))),
        ]),
      );
}
