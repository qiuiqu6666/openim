import '../fund_models.dart';

/// Product visibility for new payment and wallet entry points.
/// Historical records and transport balances retain their original currencies.
bool isFundCurrencyVisible(FundCurrency currency) =>
    currency != FundCurrency.trx;

bool isFundCurrencyCodeVisible(String code) =>
    code.trim().toUpperCase() != 'TRX';
