import 'package:flutter/material.dart';

/// 平台币 99 图标：圆形裁剪并略放大裁边。
class PlatformCoinIcon extends StatelessWidget {
  const PlatformCoinIcon({
    super.key,
    required this.size,
    this.imageScale = 1.32,
  });

  final double size;

  /// 略放大以裁掉资源图四周白边。
  final double imageScale;

  static const String assetPath = 'assets/img/platform_99.webp';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: ColoredBox(
          color: const Color(0xFF2B72FF),
          child: Center(
            child: Transform.scale(
              scale: imageScale,
              child: Image.asset(
                assetPath,
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _fallback(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Text(
        '99',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
