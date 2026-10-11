import '../../../models/group_feature_context.dart';
import '../../api/sangong_api_config.dart';
import '../../sangong_scope.dart';

/// A fixed hall runtime belongs to the route, not one refreshed page widget.
/// Nested agent pages keep the same runtime while each read is reauthorized.
class SangongAgentHallBinding {
  SangongAgentHallBinding({this.pathPrefix = SangongApiConfig.pathPrefix});
  final String pathPrefix;
  SangongRuntime? _runtime;

  void updateContext(GroupFeatureContext context) =>
      _runtime?.updateContext(context);

  SangongRuntime bind(
      GroupFeatureContext context, String tenantID, String name) {
    final previous = _runtime;
    if (previous != null) {
      if (previous.selectedAgentTenantId != tenantID) {
        throw StateError('代理群归属已变化，请重新进入');
      }
      previous.updateContext(context);
      return previous;
    }
    return _runtime = SangongRuntime(context,
        pathPrefix: pathPrefix,
        selectedAgentTenantId: tenantID,
        selectedAgentHallName: name);
  }

  void dispose() {
    _runtime?.dispose();
    _runtime = null;
  }
}
