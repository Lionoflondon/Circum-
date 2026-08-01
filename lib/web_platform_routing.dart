enum CircumWebSurface { public, sender, rider, gifts, vanguard, admin }

enum CircumSenderEntry { dashboard, healthPlus, business, profile }

class CircumWebRouteResolution {
  const CircumWebRouteResolution({
    required this.surface,
    required this.canonicalPath,
    this.senderEntry = CircumSenderEntry.dashboard,
    this.legacyRedirectPath,
  });

  final CircumWebSurface surface;
  final String canonicalPath;
  final CircumSenderEntry senderEntry;
  final String? legacyRedirectPath;
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
  final segments = path
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
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
    default:
      return const CircumWebRouteResolution(
        surface: CircumWebSurface.public,
        canonicalPath: '/',
      );
  }
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
