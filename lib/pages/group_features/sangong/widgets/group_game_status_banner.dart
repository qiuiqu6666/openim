// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/models/group_game_round_status.dart';

/// 群聊头部下方的三公游戏状态条。
class GroupGameStatusBanner extends StatelessWidget {
  const GroupGameStatusBanner({
    super.key,
    required this.doorCount,
    required this.roundStatus,
  });

  final int doorCount;
  final GroupGameRoundStatus roundStatus;

  static const Color _bannerBlue = Color(0xFF5AABF0);
  static const Color _doorNumberBlue = Color(0xFF2D8CFF);
  static const Color _bankerDoorBorder = Color(0xFFFFB300);
  static const Color _bankerDoorFill = Color(0xFFFFF8E1);
  static const Color _bankerDoorNumber = Color(0xFFE65100);
  static const Color _bankerBadgeFill = Color(0xFFFF9800);

  static const double _minDoorBoxSize = 34;
  static const double _maxDoorBoxSize = 48;

  /// 6 门为产品默认布局，单独调过间距与字号。
  static const int _comfortDoorCount = 6;
  static const double _comfortSixGap = 8;
  static const double _comfortSixBoxCap = 46;
  static const double _comfortSixBoxFloor = 40;

  static double _resolveDoorGap(int count) {
    if (count == _comfortDoorCount) {
      return _comfortSixGap;
    }
    return count <= 4 ? 10 : 6;
  }

  static double _resolveDoorBoxSize(int count, double maxWidth) {
    if (count <= 0 || maxWidth <= 0) {
      return _comfortSixBoxCap;
    }
    final gap = _resolveDoorGap(count);
    final gaps = (count - 1) * gap;
    final fitted = (maxWidth - gaps) / count;

    if (count == _comfortDoorCount) {
      return fitted.clamp(_comfortSixBoxFloor, _comfortSixBoxCap);
    }
    if (fitted >= _maxDoorBoxSize) {
      return _maxDoorBoxSize;
    }
    return fitted.clamp(_minDoorBoxSize, _maxDoorBoxSize);
  }

  @override
  Widget build(BuildContext context) {
    final count = doorCount.clamp(2, 10);
    final values = roundStatus.doorValuesForCount(count);
    final statusText = roundStatus.formatStatusLine();
    final bankerDoor = roundStatus.bankerDoor;

    return ColoredBox(
      color: _bannerBlue,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          bankerDoor != null ? 14 : (count == _comfortDoorCount ? 11 : 10),
          12,
          8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final gap = _resolveDoorGap(count);
                final boxSize =
                    _resolveDoorBoxSize(count, constraints.maxWidth);
                final numberFontSize = count == _comfortDoorCount
                    ? 20.0
                    : (boxSize * 0.48).clamp(16.0, 22.0);
                final betFontSize = count == _comfortDoorCount ? 13.0 : 14.0;

                return Row(
                  mainAxisAlignment: count <= 4
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.spaceBetween,
                  children: [
                    for (var index = 0; index < count; index++) ...[
                      if (index > 0 && count <= 4) SizedBox(width: gap),
                      _DoorColumn(
                        doorNumber: index + 1,
                        betTotal: values[index],
                        boxSize: boxSize,
                        numberFontSize: numberFontSize,
                        betFontSize: betFontSize,
                        isBankerDoor:
                            bankerDoor != null && bankerDoor == index + 1,
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoorColumn extends StatelessWidget {
  const _DoorColumn({
    required this.doorNumber,
    required this.betTotal,
    required this.boxSize,
    required this.numberFontSize,
    required this.betFontSize,
    required this.isBankerDoor,
  });

  final int doorNumber;
  final int betTotal;
  final double boxSize;
  final double numberFontSize;
  final double betFontSize;
  final bool isBankerDoor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: boxSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: boxSize,
            height: boxSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isBankerDoor
                    ? GroupGameStatusBanner._bankerDoorFill
                    : Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: isBankerDoor
                    ? Border.all(
                        color: GroupGameStatusBanner._bankerDoorBorder,
                        width: 3,
                      )
                    : null,
                boxShadow: isBankerDoor
                    ? [
                        BoxShadow(
                          color: GroupGameStatusBanner._bankerDoorBorder
                              .withValues(alpha: 0.65),
                          blurRadius: 8,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Text(
                      '$doorNumber',
                      style: TextStyle(
                        color: isBankerDoor
                            ? GroupGameStatusBanner._bankerDoorNumber
                            : GroupGameStatusBanner._doorNumberBlue,
                        fontSize: numberFontSize,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                  if (isBankerDoor)
                    Positioned(
                      top: -5,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: GroupGameStatusBanner._bankerBadgeFill,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            child: Text(
                              '庄',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$betTotal',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isBankerDoor ? const Color(0xFFFFF9C4) : Colors.white,
              fontSize: betFontSize,
              fontWeight: isBankerDoor ? FontWeight.w800 : FontWeight.w600,
              height: 1.1,
              shadows: isBankerDoor
                  ? [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
