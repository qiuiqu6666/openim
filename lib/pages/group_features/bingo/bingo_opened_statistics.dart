import 'package:flutter/material.dart';
import '../mark_six/models/mark_six_draw.dart';
import '../mark_six/widgets/mark_six_opened_statistics.dart';
import 'bingo_draw.dart';

/// Adapt only public Bingo result attributes; no Mark Six data requests.
class BingoOpenedStatistics extends StatelessWidget {
  const BingoOpenedStatistics({super.key, required this.draws});
  final List<BingoDraw> draws;

  @override
  Widget build(BuildContext context) => MarkSixOpenedStatistics(
        includeTies: true,
        draws: draws
            .map((draw) => MarkSixDraw({
                  'issue': draw.issue,
                  'status': 'drawn',
                  'attributes': {
                    'special': draw.special.number,
                    'size': draw.special.bigSmall,
                    'parity': draw.special.oddEven,
                    'zodiac': draw.special.zodiac,
                    'wave': draw.special.color == Colors.red
                        ? '红'
                        : draw.special.color == Colors.blue
                            ? '蓝'
                            : draw.special.color == Colors.green
                                ? '绿'
                                : '—',
                  },
                }))
            .toList(),
      );
}
