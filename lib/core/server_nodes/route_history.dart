import 'package:shared_preferences/shared_preferences.dart';
import 'node_endpoint.dart';

/// Stores only an allowlisted route identity, never credentials or SDK config.
class RouteHistory {
  static const key = 'network.last_successful_route.v1';
  static final _routes = [...NodeEndpoint.builtIn, NodeEndpoint.shield];

  static Future<NodeEndpoint?> read() async {
    final value = (await SharedPreferences.getInstance()).getString(key);
    for (final route in _routes) {
      if (route.signature == value) return route;
    }
    return null;
  }

  static Future<void> remember(NodeEndpoint route) async {
    if (!_routes.any((node) => node.signature == route.signature)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(key) != route.signature) {
        await prefs.setString(key, route.signature);
      }
    } catch (_) {
      // Storage failure must not turn a working connection into a login error.
    }
  }
}
