import 'role_access.dart';

/// Role recognition never substitutes for the backend account bootstrap.
Future<bool> ensureWebSenderBootstrap({
  required Set<CircumRole> roles,
  required Future<Map<String, dynamic>> Function() ensureAccount,
}) async {
  if (!RoleAccessPolicy.rolesCanAccessSender(roles) &&
      (roles.contains(CircumRole.rider) || roles.contains(CircumRole.admin))) {
    return false;
  }
  final result = await ensureAccount();
  return result['allowed'] == true;
}
