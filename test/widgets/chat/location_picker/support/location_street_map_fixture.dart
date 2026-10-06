import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

/// Test-only stand-in for the native map surface; no production map is faked.
/// Coordinates follow injected map callbacks rather than a device GPS or server.
class LocationStreetMapFixture extends StatefulWidget {
  const LocationStreetMapFixture(
      {super.key,
      required this.center,
      required this.onSelected,
      required this.onReady,
      this.enabled = true});
  final LatLng center;
  final ValueChanged<LatLng> onSelected;
  final VoidCallback onReady;
  final bool enabled;

  @override
  State<LocationStreetMapFixture> createState() =>
      _LocationStreetMapFixtureState();
}

class _LocationStreetMapFixtureState extends State<LocationStreetMapFixture> {
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady();
    });
  }

  void _emit(Offset offset) {
    if (!widget.enabled) return;
    widget.onSelected(LatLng(widget.center.latitude - offset.dy * .0001,
        widget.center.longitude + offset.dx * .0001));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, size) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (tap) => _emit(tap.localPosition -
                Offset(size.maxWidth / 2, size.maxHeight / 2)),
            onPanStart: (_) => _drag = Offset.zero,
            onPanUpdate: (event) => _drag += event.delta,
            onPanEnd: (_) => _emit(-_drag),
            child: CustomPaint(
                painter: _StreetPainter(),
                child: Stack(children: [
                  const Center(
                      child: Icon(Icons.location_on,
                          size: 38, color: Color(0xFF1687FF))),
                  const Positioned(
                      left: 12,
                      bottom: 10,
                      child: Text('LOCAL TEST MAP',
                          style: TextStyle(
                              color: Color(0xFF75847D), fontSize: 10))),
                  Positioned(
                      left: 16,
                      top: 14,
                      child: Text('河畔公园',
                          style: TextStyle(
                              color: const Color(0xFF6D8865),
                              fontSize: 12,
                              fontFamily: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.fontFamily))),
                ])),
          ));
}

class _StreetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFEDF1EB));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * .05, size.height * .05, size.width * .27,
                size.height * .28),
            const Radius.circular(10)),
        Paint()..color = const Color(0xFFCCE0C3));
    final river = Path()
      ..moveTo(size.width * .58, 0)
      ..cubicTo(size.width * .4, size.height * .3, size.width * .85,
          size.height * .6, size.width * .66, size.height);
    canvas.drawPath(
        river,
        Paint()
          ..color = const Color(0xFFB5D8E7)
          ..strokeWidth = 38
          ..style = PaintingStyle.stroke);
    for (var row = 0; row < 7; row++) {
      for (var column = 0; column < 7; column++) {
        final x = column * 72.0 + 18, y = row * 86.0 + 70;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, 37, 30), const Radius.circular(4)),
            Paint()..color = const Color(0xFFD7DCCF));
      }
    }
    for (var row = 0; row < 8; row++) {
      final y = row * 86.0 + 50;
      canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = const Color(0xFFD4D8CC)
            ..strokeWidth = 16);
      canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = const Color(0xFFFFFEFA)
            ..strokeWidth = 12);
    }
    for (var column = 0; column < 13; column++) {
      final x = column * 72.0 + 4;
      canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = const Color(0xFFFFFEFA)
            ..strokeWidth = 10);
    }
  }

  @override
  bool shouldRepaint(covariant _StreetPainter oldDelegate) => false;
}
