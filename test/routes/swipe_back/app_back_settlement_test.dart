import 'package:flutter_test/flutter_test.dart';
import 'package:openim/routes/swipe_back/app_back_settlement.dart';

void main() {
  test('release preserves position and velocity for slow drags and fast flicks',
      () {
    for (final velocity in [-.2, -2.0, -6.0, 1.0]) {
      final motion = AppBackSettlement(
          position: .7, target: 0, velocity: velocity, width: 375);
      expect(motion.x(0), .7);
      expect(motion.dx(0), closeTo(velocity, .00001));
      expect(
          (motion.x(.000001) - motion.x(0)) / .000001, closeTo(velocity, .001));
      expect(motion.isDone(1), isTrue);
      expect(motion.x(1), 0);
    }
  });
  test('fast flick travels further than slow release from the same position',
      () {
    final slow =
        AppBackSettlement(position: .7, target: 0, velocity: -.2, width: 375);
    final fast =
        AppBackSettlement(position: .7, target: 0, velocity: -5, width: 375);
    expect(fast.x(.08), lessThan(slow.x(.08)));
    for (var ms = 0; ms <= 1000; ms++) {
      expect(fast.x(ms / 1000), inInclusiveRange(0, .7));
      expect(slow.x(ms / 1000), inInclusiveRange(0, .7));
    }
  });
  test('cancel keeps outgoing momentum then turns back without bouncing', () {
    final motion =
        AppBackSettlement(position: .85, target: 1, velocity: -.5, width: 375);
    expect(motion.dx(0), -.5);
    expect(motion.x(.001), lessThan(.85));
    expect(motion.dx(.08), greaterThan(0));
    for (var ms = 0; ms <= 1000; ms++) {
      expect(motion.x(ms / 1000), inInclusiveRange(0, 1));
    }
    expect(motion.x(1), 1);
    expect(motion.isDone(1), isTrue);
  });
}
