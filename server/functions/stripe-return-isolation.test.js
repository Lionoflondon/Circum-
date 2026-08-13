const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("app Stripe callers own app-hosted returns", () => {
  const gifts = read("server/functions/gifts-payment.js");
  const giftCore = read("server/functions/gifts-payment-core.js");
  const business = read("lib/app/business/business_repository.dart");
  const health = read("lib/app/health_plus/view/health_plus.dart");
  const senderBooking = read("lib/app/sender_mobile/sender_booking_canvas.dart");
  const rider = read("server/functions/rider-connect.js");

  assert.match(gifts, /giftReturnUrls/);
  assert.match(giftCore, /https:\/\/circum-app-2797c\.web\.app/);
  assert.match(business, /https:\/\/circum-app-2797c\.web\.app\/\?app=business/);
  assert.match(health, /https:\/\/circum-app-2797c\.web\.app\/\?app=health/);
  assert.match(senderBooking, /Uri\.parse\('https:\/\/circum-app-2797c\.web\.app'\)/);
  assert.match(rider, /https:\/\/circum-rider-2797c\.web\.app/);
  assert.doesNotMatch(rider, /APP_BASE_URL.*circumuk\.com/);
});

test("Website Stripe callers remain on the public Website", () => {
  const website = read("lib/website/shared/circum_website_app.dart");
  const senderBooking = read("server/functions/sender-booking.js");
  assert.match(website, /https:\/\/circumuk\.com\/\?app=business/);
  assert.match(website, /https:\/\/circumuk\.com\/send\/health\?health=success/);
  assert.match(website, /'returnUrl': 'https:\/\/circumuk\.com\/send'/);
  assert.match(senderBooking, /https:\/\/circumuk\.com\/send/);
  assert.match(website, /httpsCallable\('createGiftPayment'\)/);
  assert.doesNotMatch(website, /circum-app-2797c\.web\.app/);
});
