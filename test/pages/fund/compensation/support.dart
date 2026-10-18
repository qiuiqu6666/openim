import 'package:openim/pages/fund/compensation/data/compensation_api.dart';
import 'package:openim/pages/fund/compensation/models/compensation_detail.dart';

Map<String, dynamic> response(
        {String state = 'unclaimed',
        bool ended = false,
        String total = '3000000.00'}) =>
    {
      'activity': {
        'id': 'activity-one',
        'title': '99Chat · 老用户专属补偿',
        'description': '近期更新与服务不稳定影响了使用体验，我们深感抱歉。',
        'totalAmount': total,
        'remainingAmount': ended ? '0.00' : '682500.00',
        'minAmount': '1.00',
        'maxAmount': '100.00',
        'deadline': '2026-10-20T12:00:00Z',
        'status': ended ? 'ended' : 'active'
      },
      'serverTime': '2026-10-17T12:00:00Z',
      'state': state,
      if (state == 'claimed') ...{
        'amount': '88.66',
        'receiptID': 'fo-receipt',
        'claimedAt': '2026-10-17T11:00:00Z',
        'arrivalStatus': 'credited'
      }
    };

class FakeSource implements CompensationSource {
  CompensationDetail? current = CompensationDetail.fromJson(response());
  bool valid = true, failRead = false;
  int reads = 0, claims = 0, notified = 0;
  Future<CompensationDetail> Function()? claimAction, readAction;
  @override
  bool get sessionValid => valid;
  @override
  Future<CompensationDetail?> entry() async {
    reads++;
    return current;
  }

  @override
  Future<CompensationDetail> detail(String id) async {
    reads++;
    if (failRead) throw Exception('offline');
    return readAction != null ? await readAction!() : current!;
  }

  @override
  Future<CompensationDetail> claim(String id) async {
    claims++;
    return claimAction != null
        ? await claimAction!()
        : current = CompensationDetail.fromJson(response(state: 'claimed'));
  }

  @override
  void notifyCredited() {
    notified++;
  }
}
