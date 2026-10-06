import '../sangong_my_config.dart';

enum SangongGroupTenantStatus { configured, disabled, notFound, accessDenied }

/// A point lookup result, separate from account defaults and group permissions.
class SangongGroupTenantState {
  const SangongGroupTenantState({
    required this.status,
    this.config,
    this.tenantId = '',
    this.message = '',
    this.raw = const {},
  });

  final SangongGroupTenantStatus status;
  final SangongMyConfig? config;
  final String tenantId;
  final String message;
  final Map<String, dynamic> raw;
}
