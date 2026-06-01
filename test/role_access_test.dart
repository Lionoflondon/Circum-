import 'package:circum/app/authentication/access/role_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoleAccessPolicy', () {
    test('lets senders use sender routes only', () {
      final role = RoleAccessPolicy.resolve(user: {'userType': 'sender'});

      expect(role, CircumRole.sender);
      expect(RoleAccessPolicy.canAccessSender(role), isTrue);
      expect(RoleAccessPolicy.canAccessRider(role), isFalse);
    });

    test('lets riders use rider routes only', () {
      final role = RoleAccessPolicy.resolve(rider: {'role': 'rider'});

      expect(role, CircumRole.rider);
      expect(RoleAccessPolicy.canAccessRider(role), isTrue);
      expect(RoleAccessPolicy.canAccessSender(role), isFalse);
    });

    test('keeps admins out of public sender and rider flows', () {
      final role = RoleAccessPolicy.resolve(claims: {
        'roles': ['operations_admin'],
      });
      final roles = RoleAccessPolicy.resolveRoles(claims: {
        'roles': ['operations_admin'],
      });

      expect(role, CircumRole.admin);
      expect(RoleAccessPolicy.canAccessSender(role), isFalse);
      expect(RoleAccessPolicy.canAccessRider(role), isFalse);
      expect(RoleAccessPolicy.shouldUseAdminApp(role), isTrue);
      expect(RoleAccessPolicy.rolesCanAccessSender(roles), isFalse);
      expect(RoleAccessPolicy.rolesCanAccessRider(roles), isFalse);
      expect(RoleAccessPolicy.rolesCanAccessAdmin(roles), isTrue);
    });

    test('lets super admins also continue as senders', () {
      final roles = RoleAccessPolicy.resolveRoles(claims: {
        'roles': ['super_admin'],
      });

      expect(roles, contains(CircumRole.admin));
      expect(roles, contains(CircumRole.sender));
      expect(RoleAccessPolicy.rolesCanAccessSender(roles), isTrue);
      expect(RoleAccessPolicy.rolesCanAccessAdmin(roles), isTrue);
    });

    test('supports accounts with sender and rider roles', () {
      final roles = RoleAccessPolicy.resolveRoles(user: {
        'roles': ['sender', 'rider'],
      });

      expect(roles, contains(CircumRole.sender));
      expect(roles, contains(CircumRole.rider));
      expect(RoleAccessPolicy.rolesCanAccessSender(roles), isTrue);
      expect(RoleAccessPolicy.rolesCanAccessRider(roles), isTrue);
    });

    test('treats unknown roles as blocked', () {
      final role = RoleAccessPolicy.resolve(user: {'role': 'guest'});

      expect(role, CircumRole.unknown);
      expect(RoleAccessPolicy.canAccessSender(role), isFalse);
      expect(RoleAccessPolicy.canAccessRider(role), isFalse);
    });
  });
}
