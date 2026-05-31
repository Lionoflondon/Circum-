enum CircumRole {
  sender,
  rider,
  admin,
  unknown,
}

const adminRoleNames = {
  'super_admin',
  'operations_admin',
  'support_agent',
  'finance_admin',
  'driver_manager',
};

class RoleAccessPolicy {
  static CircumRole resolve({
    Map<String, dynamic> claims = const {},
    Map<String, dynamic> user = const {},
    Map<String, dynamic> rider = const {},
    Map<String, dynamic> adminUser = const {},
  }) {
    final roles = <String>{
      ..._roleValues(claims['adminRole']),
      ..._roleValues(claims['role']),
      ..._roleValues(claims['roles']),
      ..._roleValues(user['role']),
      ..._roleValues(user['userType']),
      ..._roleValues(rider['role']),
      ..._roleValues(rider['userType']),
      ..._roleValues(adminUser['role']),
      ..._roleValues(adminUser['roles']),
    };

    if (roles.any(adminRoleNames.contains)) return CircumRole.admin;
    if (roles.any((role) => role == 'rider' || role == 'driver')) {
      return CircumRole.rider;
    }
    if (roles.any((role) =>
        role == 'sender' ||
        role == 'customer' ||
        role == 'user' ||
        role == 'client')) {
      return CircumRole.sender;
    }
    return CircumRole.unknown;
  }

  static bool canAccessSender(CircumRole role) => role == CircumRole.sender;

  static bool canAccessRider(CircumRole role) => role == CircumRole.rider;

  static bool shouldUseAdminApp(CircumRole role) => role == CircumRole.admin;

  static Iterable<String> _roleValues(Object? value) {
    if (value == null) return const [];
    if (value is Iterable) {
      return value.map((item) => '$item'.trim().toLowerCase()).where(
            (item) => item.isNotEmpty,
          );
    }
    return ['$value'.trim().toLowerCase()].where((item) => item.isNotEmpty);
  }
}
