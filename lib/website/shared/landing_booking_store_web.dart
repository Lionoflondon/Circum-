import 'package:web/web.dart' as web;
import 'landing_booking_draft.dart';

const _key = 'circum.landingBooking.v1';

bool saveLandingBookingDraft(LandingBookingDraft draft) {
  try {
    web.window.sessionStorage.setItem(_key, draft.encode());
    return true;
  } catch (_) {
    return false;
  }
}

LandingBookingDraft? takeLandingBookingDraft() {
  try {
    final raw = web.window.sessionStorage.getItem(_key);
    web.window.sessionStorage.removeItem(_key);
    return LandingBookingDraft.decode(raw, DateTime.now());
  } catch (_) {
    return null;
  }
}
