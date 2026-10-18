import 'package:openim_common/openim_common.dart';
import '../../../../services/fund_api.dart';
import '../../../../services/fund/fund_refresh_events.dart';
import '../models/compensation_detail.dart';

abstract interface class CompensationSource {
  bool get sessionValid;
  Future<CompensationDetail?> entry();
  Future<CompensationDetail> detail(String id);
  Future<CompensationDetail> claim(String id);
  void notifyCredited();
}

class CompensationApi implements CompensationSource {
  CompensationApi({FundApi? transport, bool Function()? sessionCheck})
      : _transport = transport ?? FundApi(),
        _sessionCheck = sessionCheck,
        _owner = FundRefreshEvents.currentAccountKey,
        _token = DataSp.chatToken;
  final FundApi _transport;
  final bool Function()? _sessionCheck;
  final String _owner;
  final String? _token;
  @override
  bool get sessionValid =>
      _sessionCheck?.call() ??
      (!_owner.endsWith(':') &&
          _token?.isNotEmpty == true &&
          _owner == FundRefreshEvents.currentAccountKey &&
          _token == DataSp.chatToken);
  Future<Map<String, dynamic>> _call(String action, [String? id]) async {
    if (!sessionValid) throw const FundApiException(-2, 'Session changed');
    final json = await _transport.requestData('/chat/fund/compensation/$action',
        data: id == null ? {} : {'id': id}, mutation: action == 'claim');
    if (!sessionValid) throw const FundApiException(-2, 'Session changed');
    return json;
  }

  @override
  Future<CompensationDetail?> entry() async {
    final json = await _call('entry');
    if (!json.containsKey('activity')) {
      throw const FormatException('Missing activity');
    }
    return json['activity'] == null ? null : CompensationDetail.fromJson(json);
  }

  Future<CompensationDetail> _forID(String action, String id) async {
    final result = CompensationDetail.fromJson(await _call(action, id));
    if (result.id != id) throw const FormatException('Activity mismatch');
    return result;
  }

  @override
  Future<CompensationDetail> detail(String id) => _forID('detail', id);
  @override
  Future<CompensationDetail> claim(String id) => _forID('claim', id);
  @override
  void notifyCredited() {
    if (!sessionValid) return;
    FundRefreshEvents.notifyBalance(accountKey: _owner);
    FundRefreshEvents.notifyRecord(accountKey: _owner);
  }
}
