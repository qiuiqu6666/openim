import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/withdraw_transfer_target_validator.dart';

void main() {
  const tron = 'TP4TT7nd1UEf52K2VXL3678qGbPMYnKaqj';

  test('accepts a valid TRON Base58Check address', () {
    expect(WithdrawTransferTargetValidator.isTronAddress(tron), isTrue);
    final target = WithdrawTransferTargetValidator.resolve(
      raw: tron,
      isBlockedUserId: (_) => false,
    );
    expect(target?.isChain, isTrue);
    expect(target?.value, tron);
  });

  test('extracts a TRON address from tron URI and surrounding text', () {
    expect(
      WithdrawTransferTargetValidator.extractTronAddress('tron:$tron'),
      tron,
    );
    expect(
      WithdrawTransferTargetValidator.extractTronAddress('receive: $tron'),
      tron,
    );
  });

  test('rejects an address with a broken checksum', () {
    const broken = 'TP4TT7nd1UEf52K2VXL3678qGbPMYnKaqk';
    expect(WithdrawTransferTargetValidator.isTronAddress(broken), isFalse);
    expect(
      WithdrawTransferTargetValidator.resolve(
        raw: broken,
        isBlockedUserId: (_) => false,
      ),
      isNull,
    );
  });

  test('resolves a valid 10-character 99chat id as friend target', () {
    const id = 'Ab12Cd34Ef';
    final target = WithdrawTransferTargetValidator.resolve(
      raw: '@$id',
      isBlockedUserId: (_) => false,
    );
    expect(target?.isFriend, isTrue);
    expect(target?.value, id);
  });

  test('uses friend nickname resolver before raw id fallback', () {
    final target = WithdrawTransferTargetValidator.resolve(
      raw: 'Alice',
      isBlockedUserId: (_) => false,
      resolveFriendUserId: (value) => value == 'Alice' ? 'Ab12Cd34Ef' : null,
    );
    expect(target?.isFriend, isTrue);
    expect(target?.value, 'Ab12Cd34Ef');
  });

  test('blocks official/system user ids supplied by host policy', () {
    final target = WithdrawTransferTargetValidator.resolve(
      raw: 'Ab12Cd34Ef',
      isBlockedUserId: (id) => id == 'Ab12Cd34Ef',
    );
    expect(target, isNull);
  });
}
