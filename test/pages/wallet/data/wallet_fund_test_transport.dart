import 'package:dio/dio.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/services/fund_api.dart';

class WalletFundTestTransport {
  WalletFundTestTransport() {
    client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      final response = Response<dynamic>(
          requestOptions: request, statusCode: statusCode, data: body);
      if (failure != null) {
        handler.reject(DioException(
            requestOptions: request,
            type: failure!,
            response: failure == DioExceptionType.badResponse ? response : null,
            message: 'raw diagnostics contain 123456'));
      } else {
        handler.resolve(response);
      }
    }));
    fund = FundApi(
        client: client,
        baseUrl: 'https://chat.example.test///',
        tokenProvider: () => token);
    wallet = WalletFundApi(api: fund);
  }

  final Dio client = Dio();
  final List<RequestOptions> requests = [];
  late final FundApi fund;
  late final WalletFundApi wallet;
  String? token = 'chat-token';
  int statusCode = 200;
  DioExceptionType? failure;
  Map<String, dynamic> body = {'errCode': 0, 'data': <String, dynamic>{}};

  void respond(Map<String, dynamic> data) =>
      body = {'errCode': 0, 'data': data};
  void close() => client.close(force: true);
}

Map<String, dynamic> walletTestOrder({
  String biz = 'withdraw',
  String status = 'withdraw_done',
  String currency = 'USDT',
  String amount = '10',
}) =>
    {
      'orderID': 'order-1',
      'clientOrderID': 'client-1',
      'biz': biz,
      'currency': currency,
      'amount': amount,
      'status': status,
      if (biz == 'withdraw') 'toAddress': 'T-destination',
      if (biz == 'withdraw') 'fee': '1.234567',
    };

Map<String, dynamic> walletTestDeposit({String txID = 'tx-1'}) => {
      'tx_id': txID,
      'currency': 'USDT',
      'amount': '12.500001',
      'address': 'T-deposit',
      'height': 86854800,
      'status': 'credited',
      'confirmations': 1,
    };

Map<String, dynamic> walletTestAddress() => {
      'status': 'ready',
      'network': 'TRON',
      'address': 'T-deposit',
      'currencies': ['USDT', 'TRX'],
      'confirmations': 1,
      'usdtContract': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      'currencyRules': <String, dynamic>{
        for (final code in ['USDT', 'TRX'])
          code: <String, dynamic>{
            'minDepositAmount': code == 'USDT' ? '0.1' : '1',
            'minWithdrawAmount': '10',
            'withdrawFee': '0.000001',
            'withdrawFeeCurrency': code,
            'receivingAccountType': 'wallet',
            'estimatedArrivalSeconds': 120,
            'withdrawUnlockConfirmations': 33,
            'memoRequired': false,
          },
      },
    };
