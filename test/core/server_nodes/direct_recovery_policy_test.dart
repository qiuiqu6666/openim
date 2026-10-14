import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/direct_recovery_policy.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';

void main() {
  final epoch = DateTime(2026, 10, 14);
  List<NodeAvailability> checks(bool primary, bool backup) => [
        NodeAvailability(NodeEndpoint.direct,
            available: primary, latencyMs: 10),
        NodeAvailability(NodeEndpoint.backup, available: backup, latencyMs: 10),
      ];
  test('same direct route must pass three spaced full-service checks', () {
    final policy = DirectRecoveryPolicy();
    expect(policy.observe(checks(true, true), epoch), isNull);
    expect(
        policy.observe(
            checks(true, true), epoch.add(const Duration(seconds: 1))),
        isNull);
    expect(
        policy.observe(
            checks(true, true), epoch.add(const Duration(seconds: 30))),
        isNull);
    expect(
        policy.observe(
            checks(true, true), epoch.add(const Duration(seconds: 60))),
        NodeEndpoint.direct);
  });
  test('blocked primary does not prevent recovery through second direct route',
      () {
    final policy = DirectRecoveryPolicy();
    policy.observe(checks(false, true), epoch);
    policy.observe(checks(false, true), epoch.add(const Duration(seconds: 30)));
    expect(
        policy.observe(
            checks(false, true), epoch.add(const Duration(seconds: 60))),
        NodeEndpoint.backup);
  });
  test('failure resets consecutive successes even between sample intervals',
      () {
    final policy = DirectRecoveryPolicy();
    policy.observe(checks(true, false), epoch);
    policy.observe(checks(false, false), epoch.add(const Duration(seconds: 1)));
    policy.observe(checks(true, false), epoch.add(const Duration(seconds: 30)));
    expect(
        policy.observe(
            checks(true, false), epoch.add(const Duration(seconds: 60))),
        isNull);
    expect(
        policy.observe(
            checks(true, false), epoch.add(const Duration(seconds: 90))),
        NodeEndpoint.direct);
  });
  test('failed return requires cooldown then three fresh successes', () {
    final policy = DirectRecoveryPolicy()..failed(epoch);
    expect(
        policy.observe(
            checks(true, true), epoch.add(const Duration(minutes: 9))),
        isNull);
    expect(
        policy.observe(
            checks(true, true), epoch.add(const Duration(minutes: 10))),
        isNull);
    policy.observe(checks(true, true), epoch.add(const Duration(seconds: 630)));
    expect(
        policy.observe(
            checks(true, true), epoch.add(const Duration(minutes: 11))),
        NodeEndpoint.direct);
  });
  test('network or session reset discards previous recovery evidence', () {
    final policy = DirectRecoveryPolicy();
    policy.observe(checks(true, false), epoch);
    policy.observe(checks(true, false), epoch.add(const Duration(seconds: 30)));
    policy.reset();
    expect(
        policy.observe(
            checks(true, false), epoch.add(const Duration(seconds: 60))),
        isNull);
  });
}
