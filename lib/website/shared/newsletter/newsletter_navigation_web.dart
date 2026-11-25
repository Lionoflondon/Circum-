import 'package:web/web.dart' as web;

void openNewsletterUri(Uri uri) => web.window.location.assign(uri.toString());
