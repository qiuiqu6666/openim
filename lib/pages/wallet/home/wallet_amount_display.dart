/// Missing or malformed amounts display zero without changing account data.
String walletAmountDisplay(String value) {
  final numeric = value.replaceAll(RegExp(r'[¥$≈,\s]'), '');
  if (!RegExp(r'^[+-]?\d+(?:\.\d+)?$').hasMatch(numeric)) {
    return '0.00';
  }
  return value;
}
