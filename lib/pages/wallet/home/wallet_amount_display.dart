/// Missing or malformed amounts stay unknown; only server zero is shown as zero.
String walletAmountDisplay(String value) {
  final numeric = value.replaceAll(RegExp(r'[¥$≈,\s]'), '');
  if (!RegExp(r'^[+-]?\d+(?:\.\d+)?$').hasMatch(numeric)) {
    return '--';
  }
  return value;
}
