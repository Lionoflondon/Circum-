enum CircumWebSurface {
  public,
  sender,
  rider,
  gifts,
  vanguard,
  support,
  deleteAccount,
  privacyPolicy,
  terms,
  cookiePolicy,
  newsletterPreferences,
  admin,
}

enum CircumSenderEntry { dashboard, healthPlus, business, profile }

class CircumWebRouteResolution {
  const CircumWebRouteResolution({
    required this.surface,
    required this.canonicalPath,
    this.senderEntry = CircumSenderEntry.dashboard,
    this.legacyRedirectPath,
    this.referralCode,
    this.senderNotificationDestination,
  });

  final CircumWebSurface surface;
  final String canonicalPath;
  final CircumSenderEntry senderEntry;
  final String? legacyRedirectPath;
  final String? referralCode;
  final Map<String, String>? senderNotificationDestination;
}

const circumPublicWebIdentity = 'circum-public-web';
const circumSenderWebIdentity = 'circum-sender-web';
const circumRiderWebIdentity = 'circum-rider-web';

String normalizeCircumWebPath(String rawPath) {
  if (rawPath.trim().isEmpty) return '/';
  var path = rawPath.trim();
  if (!path.startsWith('/')) path = '/$path';
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

String senderNotificationWebPath(Map<String, dynamic> destination) {
  const routes = {
    'tracking',
    'conversation',
    'wallet',
    'gift',
    'health',
    'business',
    'profile',
    'activity',
  };
  final route = '${destination['route'] ?? ''}'.trim().toLowerCase();
  if (!routes.contains(route)) return '/send';
  final id =
      '${destination['deliveryId'] ?? destination['chatId'] ?? destination['giftId'] ?? destination['healthPickupId'] ?? destination['businessId'] ?? ''}'
          .trim();
  if (id.isEmpty) return '/send/notifications/$route';
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$').hasMatch(id)) {
    return '/send';
  }
  return '/send/notifications/$route/${Uri.encodeComponent(id)}';
}

String _effectiveCircumWebPath(Uri uri) {
  final fragment = uri.fragment.trim();
  if (fragment.startsWith('/')) {
    return normalizeCircumWebPath(fragment.split('?').first);
  }
  return normalizeCircumWebPath(uri.path);
}

CircumWebRouteResolution resolveCircumWebRoute(
  Uri uri, {
  required bool adminHostingTarget,
  required bool publicHostingHost,
}) {
  if (adminHostingTarget && !publicHostingHost) {
    return const CircumWebRouteResolution(
      surface: CircumWebSurface.admin,
      canonicalPath: '/',
    );
  }

  final path = _effectiveCircumWebPath(uri);
  final rawSegments = path
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  final segments = rawSegments
      .map((segment) => segment.toLowerCase())
      .toList(growable: false);
  final first = segments.isEmpty ? '' : segments.first;

  switch (first) {
    case '':
      return _legacyQueryResolution(uri) ??
          const CircumWebRouteResolution(
            surface: CircumWebSurface.public,
            canonicalPath: '/',
          );
    case 'send':
      return CircumWebRouteResolution(
        surface: CircumWebSurface.sender,
        canonicalPath: path,
        senderEntry: _senderEntryFromPath(segments),
        senderNotificationDestination: _senderNotificationDestinationFromPath(
          rawSegments,
        ),
      );
    case 'rider':
      return CircumWebRouteResolution(
        surface: CircumWebSurface.rider,
        canonicalPath: path,
      );
    case 'gifts':
      return CircumWebRouteResolution(
        surface: CircumWebSurface.gifts,
        canonicalPath: path,
      );
    case 'vanguard':
      return CircumWebRouteResolution(
        surface: CircumWebSurface.vanguard,
        canonicalPath: path,
      );
    case 'support':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.support,
        canonicalPath: '/support',
      );
    case 'delete_account':
    case 'delete-account':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.deleteAccount,
        canonicalPath: '/delete_account',
      );
    case 'privacy':
    case 'privacy-policy':
    case 'privacy_policy':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.privacyPolicy,
        canonicalPath: '/privacy_policy',
      );
    case 'terms':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.terms,
        canonicalPath: '/terms',
      );
    case 'cookie_policy':
    case 'cookies':
    case 'cookie-policy':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.cookiePolicy,
        canonicalPath: '/cookie_policy',
      );
    case 'unsubscribe':
    case 'newsletter':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.newsletterPreferences,
        canonicalPath: '/unsubscribe',
      );
    case 'join':
      var rawCode = segments.length > 1 ? segments[1] : '';
      try {
        rawCode = Uri.decodeComponent(rawCode);
      } on FormatException {
        rawCode = '';
      }
      final normalized = rawCode.toUpperCase().replaceAll(
        RegExp(r'[^A-Z0-9]'),
        '',
      );
      final code = normalized.substring(0, normalized.length.clamp(0, 24));
      return CircumWebRouteResolution(
        surface: CircumWebSurface.sender,
        canonicalPath: '/send',
        referralCode: code.isEmpty ? null : code,
      );
    default:
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.public,
        canonicalPath: '/',
      );
  }
}

Map<String, String>? _senderNotificationDestinationFromPath(
  List<String> segments,
) {
  if (segments.length < 3 || segments[1] != 'notifications') return null;
  const routes = {
    'tracking',
    'conversation',
    'wallet',
    'gift',
    'health',
    'business',
    'profile',
    'activity',
  };
  final route = segments[2].toLowerCase();
  if (!routes.contains(route)) return null;
  final destination = <String, String>{'version': '1', 'route': route};
  if (segments.length > 3) {
    late final String id;
    try {
      id = Uri.decodeComponent(segments[3]);
    } on FormatException {
      return null;
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$').hasMatch(id)) {
      return null;
    }
    final key = switch (route) {
      'tracking' => 'deliveryId',
      'conversation' => 'chatId',
      'gift' => 'giftId',
      'health' => 'healthPickupId',
      'business' => 'businessId',
      _ => 'entityId',
    };
    destination[key] = id;
  }
  return destination;
}

CircumWebRouteResolution? _legacyQueryResolution(Uri uri) {
  final app = uri.queryParameters['app']?.toLowerCase().trim();
  switch (app) {
    case 'sender':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.sender,
        canonicalPath: '/send',
        legacyRedirectPath: '/send',
      );
    case 'health':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.sender,
        canonicalPath: '/send/health',
        senderEntry: CircumSenderEntry.healthPlus,
        legacyRedirectPath: '/send/health',
      );
    case 'business':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.sender,
        canonicalPath: '/send/business',
        senderEntry: CircumSenderEntry.business,
        legacyRedirectPath: '/send/business',
      );
    case 'profile':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.sender,
        canonicalPath: '/send/profile',
        senderEntry: CircumSenderEntry.profile,
        legacyRedirectPath: '/send/profile',
      );
    case 'rider':
    case 'driver':
    case 'earn':
    case 'circum-order':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.rider,
        canonicalPath: '/rider',
        legacyRedirectPath: '/rider',
      );
    case 'gifts':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.gifts,
        canonicalPath: '/gifts',
        legacyRedirectPath: '/gifts',
      );
    case 'vanguard':
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.vanguard,
        canonicalPath: '/vanguard',
        legacyRedirectPath: '/vanguard',
      );
    default:
      return null;
  }
}

CircumSenderEntry _senderEntryFromPath(List<String> segments) {
  if (segments.length < 2) return CircumSenderEntry.dashboard;
  return switch (segments[1]) {
    'health' || 'health-plus' || 'healthplus' => CircumSenderEntry.healthPlus,
    'business' => CircumSenderEntry.business,
    'profile' => CircumSenderEntry.profile,
    _ => CircumSenderEntry.dashboard,
  };
}
