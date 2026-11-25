enum WebsiteCheckoutReturn { sender, business, healthSuccess, healthCancelled }

/// Return to the approved website origin that owns the signed-in session.
Uri websiteCheckoutReturn(Uri currentPage, WebsiteCheckoutReturn target) {
  const approvedOrigins = {
    'https://circumuk.com',
    'https://www.circumuk.com',
    'https://circum-2797c.web.app',
    'https://circum-2797c.firebaseapp.com',
  };
  final currentOrigin =
      currentPage.hasAuthority && currentPage.scheme == 'https'
          ? currentPage.origin
          : '';
  final origin = approvedOrigins.contains(currentOrigin)
      ? currentOrigin
      : 'https://circumuk.com';
  final route = switch (target) {
    WebsiteCheckoutReturn.sender => '/send',
    WebsiteCheckoutReturn.business => '/?app=business',
    WebsiteCheckoutReturn.healthSuccess => '/send/health?health=success',
    WebsiteCheckoutReturn.healthCancelled => '/send/health?health=cancelled',
  };
  return Uri.parse('$origin$route');
}
