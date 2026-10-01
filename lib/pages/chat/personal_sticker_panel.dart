import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'personal_sticker_store.dart';
import 'personal_sticker_management_page.dart';

class PersonalStickerPanel extends StatefulWidget {
  const PersonalStickerPanel({
    super.key,
    required this.store,
    required this.onAdd,
    required this.onSend,
  });

  final PersonalStickerStore store;
  final Future<void> Function() onAdd;
  final Future<void> Function(PersonalSticker) onSend;

  @override
  State<PersonalStickerPanel> createState() => _PersonalStickerPanelState();
}

class _PersonalStickerPanelState extends State<PersonalStickerPanel> {
  String? _sendingID;

  @override
  void initState() {
    super.initState();
    if (widget.store.items.isEmpty) widget.store.refresh();
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('操作失败：$error')));
  }

  void _openManagement() => Navigator.of(context).push(PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => PersonalStickerManagementPage(
          store: widget.store,
          onAdd: widget.onAdd,
        ),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final store = widget.store;
          final colors = Theme.of(context).colorScheme;
          return Column(children: [
            SizedBox(
              height: 32.h,
              child: Row(children: [
                Padding(
                  padding: EdgeInsets.only(left: 12.w),
                  child: Text('添加的单个表情',
                      style: TextStyle(
                          fontSize: 13.sp, color: colors.onSurfaceVariant)),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '管理表情',
                  onPressed: _openManagement,
                  icon: Icon(Icons.more_horiz, color: colors.onSurfaceVariant),
                ),
              ]),
            ),
            if (store.loading) const LinearProgressIndicator(minHeight: 2),
            if (store.error != null)
              TextButton(
                  onPressed: store.refresh, child: const Text('加载失败，点击重试')),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(8.w, 4.h, 8.w, 8.h),
                itemCount:
                    store.items.length + 1 + (store.nextCursor == null ? 0 : 1),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8.w,
                  mainAxisSpacing: 8.h,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Center(
                      child: FractionallySizedBox(
                        widthFactor: .68,
                        heightFactor: .68,
                        child: Semantics(
                          button: true,
                          label: '添加表情',
                          child: InkWell(
                            key: const ValueKey('sticker-add-tile'),
                            onTap: _openManagement,
                            child: CustomPaint(
                              painter: _DashedTilePainter(
                                  color: colors.onSurfaceVariant),
                              child: Center(
                                child: Icon(Icons.add,
                                    size: 30.w, color: colors.onSurface),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  if (index == store.items.length + 1) {
                    return IconButton(
                      tooltip: '加载更多',
                      onPressed: store.loading ? null : store.loadMore,
                      icon: const Icon(Icons.more_horiz),
                    );
                  }
                  final item = store.items[index - 1];
                  return Center(
                    child: FractionallySizedBox(
                      widthFactor: .68,
                      heightFactor: .68,
                      child: Material(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(7.r),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey('sticker-${item.id}'),
                          onTap: () async {
                            if (_sendingID != null) return;
                            setState(() => _sendingID = item.id);
                            try {
                              await widget.onSend(item);
                            } catch (error) {
                              if (mounted) _showError(error);
                            } finally {
                              if (mounted) setState(() => _sendingID = null);
                            }
                          },
                          child: Stack(fit: StackFit.expand, children: [
                            Image.network(item.previewURL,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.broken_image_outlined,
                                    color: colors.onSurfaceVariant)),
                            if (item.isVideo)
                              Center(
                                child: Icon(Icons.play_circle_fill,
                                    size: 24.w,
                                    color: Colors.white,
                                    shadows: const [
                                      Shadow(
                                          color: Colors.black54, blurRadius: 8),
                                    ]),
                              ),
                            if (_sendingID == item.id)
                              const Center(child: CircularProgressIndicator()),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]);
        },
      );
}

class _DashedTilePainter extends CustomPainter {
  const _DashedTilePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(8)));
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 10) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedTilePainter oldDelegate) =>
      oldDelegate.color != color;
}
