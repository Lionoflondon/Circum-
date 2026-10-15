/// Keep Stripe returns on the approved website origin that owns the session.
Uri senderWebsiteCheckoutReturn(Uri currentPage) {
  const approvedOrigins = {
    'https://circumuk.com',
    'https://www.circumuk.com',
    'https://circum-2797c.web.app',
    'https://circum-2797c.firebaseapp.com',
  };
  final origin = currentPage.hasAuthority && currentPage.scheme == 'https'
      ? currentPage.origin
      : '';
  return Uri.parse(
      '${approvedOrigins.contains(origin) ? origin : 'https://circumuk.com'}/send');
}
