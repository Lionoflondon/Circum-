enum CircumRole {
  sender,
  rider,
  admin,
  unknown,
}

const adminRoleNames = {
  'admin',
  'super_admin',
  'operations_admin',
  'support_agent',
  'finance_admin',
  'driver_manager',
};

class RoleAccessPolicy {
  static const superAdminEmail = 'ayojason600@gmail.com';

  static bool isSuperAdmin({
    String? email,
    Map<String, dynamic> claims = const {},
    Map<String, dynamic> adminUser = const {},
  }) {
    final roles = <String>{
      ..._roleValues(claims['adminRole']),
      ..._roleValues(claims['role']),
      ..._roleValues(claims['roles']),
      ..._roleValues(adminUser['role']),
      ..._roleValues(adminUser['roles']),
    };
    return email?.trim().toLowerCase() == superAdminEmail &&
        roles.contains('super_admin');
  }

  static CircumRole resolve({
    Map<String, dynamic> claims = const {},
    Map<String, dynamic> user = const {},
    Map<String, dynamic> rider = const {},
    Map<String, dynamic> adminUser = const {},
  }) {
    final resolvedRoles = resolveRoles(
      claims: claims,
      user: user,
      rider: rider,
      adminUser: adminUser,
    );

    if (resolvedRoles.contains(CircumRole.admin)) return CircumRole.admin;
    if (resolvedRoles.contains(CircumRole.rider)) return CircumRole.rider;
    if (resolvedRoles.contains(CircumRole.sender)) return CircumRole.sender;
    return CircumRole.unknown;
  }

  static Set<CircumRole> resolveRoles({
    Map<String, dynamic> claims = const {},
    Map<String, dynamic> user = const {},
    Map<String, dynamic> rider = const {},
    Map<String, dynamic> adminUser = const {},
  }) {
    final trustedRoles = <String>{
      ..._roleValues(claims['adminRole']),
      ..._roleValues(claims['role']),
      ..._roleValues(claims['roles']),
      ..._roleValues(adminUser['role']),
      ..._roleValues(adminUser['roles']),
    };

    final resolvedRoles = <CircumRole>{};
    if (trustedRoles.any(adminRoleNames.contains)) {
      resolvedRoles.add(CircumRole.admin);
    }
    if (trustedRoles.contains('super_admin')) {
      resolvedRoles.add(CircumRole.sender);
      resolvedRoles.add(CircumRole.rider);
    }
    if (rider.isNotEmpty || trustedRoles.any((role) => role == 'rider')) {
      resolvedRoles.add(CircumRole.rider);
    }
    if (user.isNotEmpty ||
        trustedRoles.any((role) =>
            role == 'sender' ||
            role == 'customer' ||
            role == 'user' ||
            role == 'client')) {
      resolvedRoles.add(CircumRole.sender);
    }
    return resolvedRoles.isEmpty ? {CircumRole.unknown} : resolvedRoles;
  }

  static bool canAccessSender(CircumRole role) => role == CircumRole.sender;

  static bool canAccessRider(CircumRole role) => role == CircumRole.rider;

  static bool shouldUseAdminApp(CircumRole role) => role == CircumRole.admin;

  static bool rolesCanAccessSender(Set<CircumRole> roles) {
    return roles.contains(CircumRole.sender);
  }

  static bool rolesCanAccessRider(Set<CircumRole> roles) {
    return roles.contains(CircumRole.rider);
  }

  static bool rolesCanAccessAdmin(Set<CircumRole> roles) {
    return roles.contains(CircumRole.admin);
  }

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
