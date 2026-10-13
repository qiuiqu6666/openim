/// Process-local forwarding addresses. Never write these to server preferences.
class RuntimeNetworkRoute {
  const RuntimeNetworkRoute(
      {required this.authUrl,
      required this.apiUrl,
      required this.wsUrl,
      required this.customerServiceUrl});
  final String authUrl, apiUrl, wsUrl, customerServiceUrl;
}
