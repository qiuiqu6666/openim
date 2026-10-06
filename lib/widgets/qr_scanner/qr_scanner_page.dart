import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import 'qr_gallery_service.dart';
import 'qr_scanner_labels.dart';
import 'qr_scanner_overlay.dart';

export 'qr_gallery_service.dart';
export 'qr_scanner_labels.dart';

/// Owns QR camera/gallery UI while the caller defines the accepted payload.
/// A successful parse returns [T] through the existing Navigator route.
class QrScannerPage<T> extends StatefulWidget {
  const QrScannerPage(
      {super.key,
      required this.parseCode,
      this.keyPrefix = 'qr',
      this.invalidCodeMessage,
      this.onMyQrTap,
      this.gallery = const QrGalleryService()});

  final T? Function(String) parseCode;
  final String keyPrefix;
  final String Function(BuildContext)? invalidCodeMessage;
  final Future<void> Function()? onMyQrTap;
  final QrGalleryService gallery;

  @override
  State<QrScannerPage<T>> createState() => _QrScannerPageState<T>();
}

class _QrScannerPageState<T> extends State<QrScannerPage<T>>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  GlobalKey _qrKey = GlobalKey(debugLabel: 'qr-reader');
  QRViewController? _controller;
  StreamSubscription<Barcode>? _subscription;
  late final _scanAnimation = AnimationController(
      vsync: this, duration: QrScannerTokens.scanDuration, value: .5);
  Timer? _startTimer;
  Completer<void>? _foregroundReady;
  Future<void> _cameraWork = Future<void>.value();
  AppLifecycleState? _lifecycle;
  bool _routeCurrent = true;
  bool _handled = false;
  bool _closed = false;
  bool _permissionKnown = false;
  bool _denied = false;
  bool _galleryBusy = false;
  bool _myQrBusy = false;
  bool _flashAvailable = false;
  bool _flashOn = false;
  bool _flashBusy = false;
  bool _cameraFailed = false;

  bool get _ownsPage => mounted && !_closed && !_handled && _routeCurrent;

  bool get _activePage =>
      _ownsPage &&
      (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);

  bool get _canScan => _activePage && !_galleryBusy && !_myQrBusy && !_denied;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _watchCameraStart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // isCurrentOf registers an InheritedModel dependency for this route aspect.
    // Covering/uncovering this page invokes this hook without a global observer.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current != _routeCurrent) {
      _routeCurrent = current;
      if (!current) _releaseForegroundWaiter();
      _syncCamera();
    }
    _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) _releaseForegroundWaiter();
    if (state == AppLifecycleState.resumed &&
        _denied &&
        !_galleryBusy &&
        !_myQrBusy &&
        _routeCurrent) {
      _restartCamera();
      return;
    }
    _syncCamera();
  }

  void _releaseForegroundWaiter() {
    final pending = _foregroundReady;
    _foregroundReady = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<bool> _waitForForeground() async {
    if (!_ownsPage || ModalRoute.of(context)?.isCurrent != true) return false;
    if (!_activePage) {
      final pending = _foregroundReady ??= Completer<void>();
      await pending.future;
    }
    if (!mounted || !_activePage) return false;
    return ModalRoute.of(context)?.isCurrent == true;
  }

  void _syncAnimation() {
    if (!mounted || _closed) return;
    if (_canScan &&
        _permissionKnown &&
        !_cameraFailed &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!_scanAnimation.isAnimating) _scanAnimation.repeat(reverse: true);
    } else {
      _scanAnimation.stop();
    }
  }

  void _watchCameraStart() {
    _startTimer?.cancel();
    _startTimer = Timer(QrScannerTokens.cameraStartTimeout, () {
      if (!mounted || _closed || _permissionKnown) return;
      setState(() => _cameraFailed = true);
      _syncAnimation();
    });
  }

  void _syncCamera() {
    _syncAnimation();
    // Serialize native commands and read the latest desired state at execution
    // time so an older resume cannot follow a newer background transition.
    _cameraWork = _cameraWork.then((_) async {
      final controller = _controller;
      if (_closed || controller == null || controller.disposed) return;
      try {
        if (_canScan) {
          if (controller.hasPermissions) await controller.resumeCamera();
        } else {
          await controller.pauseCamera();
        }
      } catch (_) {
        if (_canScan && mounted && identical(controller, _controller)) {
          setState(() => _cameraFailed = true);
          _syncAnimation();
        }
      }
    });
    unawaited(_cameraWork);
  }

  void _onCreated(QRViewController controller) {
    if (_closed || !mounted || _handled) return;
    _controller = controller;
    unawaited(_subscription?.cancel());
    _subscription = controller.scannedDataStream.listen((barcode) {
      if (!mounted ||
          !_canScan ||
          !identical(controller, _controller) ||
          controller.disposed ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _returnCode(barcode.code);
    });
    unawaited(_refreshFlash(controller));
    _syncCamera();
  }

  bool _returnCode(String? code) {
    if (!_activePage || ModalRoute.of(context)?.isCurrent != true) return false;
    final result = widget.parseCode(code?.trim() ?? '');
    if (result == null) return false;
    _handled = true;
    _syncCamera();
    Navigator.of(context).pop<T>(result);
    return true;
  }

  void _onPermission(QRViewController controller, bool granted) {
    if (!mounted || _closed) return;
    _startTimer?.cancel();
    setState(() {
      _permissionKnown = true;
      _denied = !granted;
      _cameraFailed = false;
      if (!granted) _flashAvailable = false;
    });
    if (granted) unawaited(_refreshFlash(controller));
    _syncCamera();
  }

  Future<void> _refreshFlash(QRViewController controller) async {
    if (!controller.hasPermissions || controller.disposed) return;
    try {
      final features = await controller.getSystemFeatures();
      final enabled = features.hasFlash
          ? await controller.getFlashStatus() ?? false
          : false;
      if (!mounted ||
          _closed ||
          controller.disposed ||
          !identical(controller, _controller)) {
        return;
      }
      setState(() {
        _flashAvailable = features.hasFlash;
        _flashOn = enabled;
      });
    } catch (_) {
      // A camera without a torch still supports scanning and gallery images.
    }
  }

  Future<void> _toggleFlash() async {
    if (!_canScan || !_flashAvailable || _flashBusy) return;
    setState(() => _flashBusy = true);
    _cameraWork = _cameraWork.then((_) async {
      final controller = _controller;
      if (!_canScan || controller == null || controller.disposed) return;
      try {
        await controller.toggleFlash();
        final enabled = await controller.getFlashStatus() ?? false;
        if (!mounted || _closed || !identical(controller, _controller)) return;
        setState(() => _flashOn = enabled);
      } catch (_) {
        if (mounted && _activePage) {
          _message(QrScannerLabels.of(context).flashUnavailable);
        }
      }
    });
    await _cameraWork;
    if (mounted && !_closed) setState(() => _flashBusy = false);
  }

  Future<void> _pickGallery() async {
    if (!_activePage || _galleryBusy || _myQrBusy) return;
    setState(() => _galleryBusy = true);
    _syncCamera();
    try {
      await _cameraWork;
      if (!_activePage) return;
      final path = await widget.gallery.pickImage();
      // Native pickers may reply before Flutter receives the resumed event.
      // Retain the selected image until this route is foregrounded again.
      if (path == null || !await _waitForForeground()) return;
      final code = await widget.gallery.readCode(path);
      if (!await _waitForForeground() || !mounted) return;
      if (!_returnCode(code)) {
        _message(widget.invalidCodeMessage?.call(context) ??
            QrScannerLabels.of(context).invalidCode);
      }
    } catch (_) {
      if (mounted && _activePage) {
        _message(QrScannerLabels.of(context).readImageFailed);
      }
    } finally {
      if (mounted && !_closed) {
        setState(() => _galleryBusy = false);
        _syncCamera();
      }
    }
  }

  Future<void> _openMyQr() async {
    if (!_activePage || _galleryBusy || _myQrBusy || widget.onMyQrTap == null) {
      return;
    }
    setState(() => _myQrBusy = true);
    _syncCamera();
    try {
      await _cameraWork;
      if (_activePage) await widget.onMyQrTap!();
    } finally {
      if (mounted && !_closed) {
        setState(() => _myQrBusy = false);
        _syncCamera();
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _restartCamera() {
    if (!mounted || !_activePage) return;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _controller = null;
    setState(() {
      _qrKey = GlobalKey(debugLabel: 'qr-reader');
      _permissionKnown = false;
      _cameraFailed = false;
      _denied = false;
      _flashAvailable = false;
      _flashOn = false;
    });
    _watchCameraStart();
    _syncAnimation();
  }

  @override
  void dispose() {
    _closed = true;
    _releaseForegroundWaiter();
    _startTimer?.cancel();
    _scanAnimation.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
    _controller = null;
    // QRView owns and disposes its native controller when it is unmounted.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppSystemBars(
        background: QrScannerTokens.background,
        child: Scaffold(
          backgroundColor: QrScannerTokens.background,
          extendBody: true,
          body: LayoutBuilder(builder: (context, constraints) {
            final size = constraints.biggest;
            final layout = QrScannerLayout(context, size);
            final key = _qrKey;
            return Stack(fit: StackFit.expand, children: [
              QRView(
                key: key,
                formatsAllowed: const [BarcodeFormat.qrcode],
                onQRViewCreated: (controller) {
                  if (identical(key, _qrKey)) _onCreated(controller);
                },
                onPermissionSet: (controller, granted) {
                  if (identical(key, _qrKey)) {
                    _onPermission(controller, granted);
                  }
                },
                // Keep the native recognition area aligned with the drawn frame.
                overlay: QrScannerOverlayShape(
                  borderColor: Colors.transparent,
                  overlayColor: Colors.transparent,
                  borderWidth: 0,
                  borderLength: 0,
                  cutOutSize: layout.scanWindow.width,
                  cutOutBottomOffset:
                      size.height / 2 - layout.scanWindow.center.dy,
                ),
              ),
              QrScannerOverlay(
                keyPrefix: widget.keyPrefix,
                showMyQr: widget.onMyQrTap != null,
                layout: layout,
                animation: _scanAnimation,
                onBack: () => Navigator.of(context).pop(),
                onAlbum: _activePage && !_galleryBusy && !_myQrBusy
                    ? _pickGallery
                    : null,
                onFlash: _canScan && _flashAvailable && !_flashBusy
                    ? _toggleFlash
                    : null,
                onMyQr: _activePage &&
                        !_galleryBusy &&
                        !_myQrBusy &&
                        widget.onMyQrTap != null
                    ? _openMyQr
                    : null,
                flashOn: _flashOn,
              ),
              if (_galleryBusy || !_permissionKnown || _denied || _cameraFailed)
                Positioned.fromRect(
                  rect: layout.scanWindow.deflate(AppTokens.s3),
                  child: _cameraState(),
                ),
            ]);
          }),
        ),
      );

  Widget _cameraState() => ColoredBox(
        color: QrScannerTokens.background.withValues(alpha: .54),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.s4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_galleryBusy || (!_permissionKnown && !_cameraFailed))
                const CircularProgressIndicator(
                    color: QrScannerTokens.foreground)
              else ...[
                const Icon(Icons.videocam_off_rounded,
                    color: QrScannerTokens.foreground,
                    size: QrScannerTokens.flashIconSize),
                const SizedBox(height: AppTokens.s4),
                Text(
                    _denied
                        ? QrScannerLabels.of(context).cameraDenied
                        : QrScannerLabels.of(context).cameraFailed,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: QrScannerTokens.foreground)),
                const SizedBox(height: AppTokens.s4),
                OutlinedButton(
                  onPressed: _denied ? () => openAppSettings() : _restartCamera,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: QrScannerTokens.foreground,
                      side:
                          const BorderSide(color: QrScannerTokens.foreground)),
                  child: Text(_denied
                      ? QrScannerLabels.of(context).openSettings
                      : QrScannerLabels.of(context).retry),
                ),
              ],
            ]),
          ),
        ),
      );
}
