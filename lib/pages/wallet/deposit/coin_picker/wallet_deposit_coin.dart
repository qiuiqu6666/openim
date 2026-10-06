import '../../data/wallet_fund_api.dart';

/// Searchable labels for currencies explicitly enabled by the deposit endpoint.
class WalletDepositCoin {
  const WalletDepositCoin({
    required this.currency,
    required this.name,
    this.contractAddress = '',
  });

  final FundCurrency currency;
  final String name;
  final String contractAddress;
  String get code => currency.code;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    return code.toLowerCase().contains(normalized) ||
        name.toLowerCase().contains(normalized) ||
        (contractAddress.isNotEmpty &&
            contractAddress.toLowerCase().contains(normalized));
  }

  static List<WalletDepositCoin> fromAddress(WalletDepositAddress address) => [
        for (final currency in address.currencies)
          if (currency != FundCurrency.bi99)
            WalletDepositCoin(
              currency: currency,
              name: currency == FundCurrency.usdt ? 'Tether' : 'TRON',
              contractAddress:
                  currency == FundCurrency.usdt ? address.usdtContract : '',
            ),
      ];
}
