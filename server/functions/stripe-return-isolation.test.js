const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("app Stripe callers own app-hosted returns", () => {
  const gifts = read("server/functions/gifts-payment.js");
  const ownership = read("server/functions/stripe-return-ownership.js");
  const business = read("lib/app/business/business_repository.dart");
  const businessView = read("lib/app/business/business_view.dart");
  const giftPayment = read("lib/app/sender_mobile/gift_payment_view.dart");
  const giftCampaign = read("lib/app/sender_mobile/gift_campaign_view.dart");
  const health = read("lib/app/health_plus/view/health_plus.dart");
  const senderBooking = read("lib/app/sender_mobile/sender_booking_canvas.dart");
  const senderRouting = read("lib/app/sender_mobile/sender_stripe_return_routing.dart");
  const giftReturn = read("lib/app/sender_mobile/gift_payment_return_view.dart");
  const rider = read("server/functions/rider-connect.js");

  assert.match(gifts, /giftReturnUrls/);
  assert.match(ownership, /https:\/\/circum-app-2797c\.web\.app/);
  assert.match(business, /'returnOwner': 'sender_app'/);
  assert.match(giftPayment, /'returnOwner': 'sender_app'/);
  assert.match(giftCampaign, /'returnOwner': 'sender_app'/);
  assert.match(health, /'returnOwner': 'sender_app'/);
  assert.match(senderBooking, /returnOwner: kIsWeb \? 'sender_app' : ''/);
  assert.match(businessView, /webOnlyWindowName: kIsWeb \? '_self' : null/);
  assert.match(senderRouting, /senderGiftPaymentReturnRouteName/);
  assert.match(senderRouting, /senderHealthReturnRouteName/);
  assert.match(senderRouting, /senderBusinessReturnRouteName/);
  assert.match(senderRouting, /senderWalletReturnRouteName/);
  assert.match(senderRouting, /wallet_topup/);
  assert.match(giftReturn, /httpsCallable\('finalizeGiftPayment'\)/);
  assert.match(rider, /https:\/\/circum-rider-2797c\.web\.app/);
  assert.doesNotMatch(rider, /RIDER_APP_BASE_URL|safeConfig\.rider\.base_url/);
});

test("Website Stripe callers remain on the public Website", () => {
  const website = read("lib/website/shared/circum_website_app.dart");
  const ownership = read("server/functions/stripe-return-ownership.js");
  const ownerDeclarations = website.match(/'returnOwner': 'website'/g) || [];
  assert.ok(ownerDeclarations.length >= 5);
  assert.match(ownership, /https:\/\/circumuk\.com\/send\/business/);
  assert.match(ownership, /https:\/\/circumuk\.com\/gifts/);
  assert.match(ownership, /https:\/\/circumuk\.com\/send\/health/);
  assert.match(ownership, /https:\/\/circumuk\.com\/send/);
  assert.match(ownership, /https:\/\/circumuk\.com\/send\/profile/);
  assert.match(website, /httpsCallable\('createGiftPayment'\)/);
  assert.doesNotMatch(website, /circum-app-2797c\.web\.app/);
});
