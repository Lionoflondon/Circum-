/* eslint-disable max-len, require-jsdoc */
"use strict";

const APP_URL = "https://circumuk.com";
const WELCOME_WORDMARK_URL = "https://circumuk.com/assets/assets/images/circum_wordmark.png";
const TERMS_URL = "https://circumuk.com/terms";
const PRIVACY_URL = "https://circumuk.com/privacy_policy";
const SUPPORT_TEXT = "Need help? Reply to this email or contact Circum support from your account.";
const gifts = require("./gift-email-templates");
const FORBIDDEN_CUSTOMER_TOKENS = [
  "roth_movement_completed",
  "sender_",
  "rider_",
  "delivery_in_progress",
  "business_invoice_",
  "health_plus_",
  "gift_story_ready",
  "firestore",
  "eventarc",
  "notificationid",
  "sourcecollection",
  "sourcerequiredstatus",
];

const text = (value) => `${value || ""}`.trim();

function escapeHtml(value) {
  return text(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;",
  }[character]));
}

function safeName(value) {
  return text(value).replace(/[<>_]/g, " ").replace(/\s+/g, " ").slice(0, 80);
}

function firstName(value) {
  return safeName(value).split(" ")[0] || "there";
}

function safeReference(value) {
  return text(value).replace(/[^A-Za-z0-9 .#/-]/g, "").slice(0, 80);
}

function money(value) {
  const amount = Number(value);
  return Number.isFinite(amount) && amount >= 0 ? `£${amount.toFixed(2)}` : "";
}

function layout({preheader, heading, paragraphs, ctaLabel = "", ctaUrl = "", footer = SUPPORT_TEXT, imageUrl = ""}) {
  const safeUrl = /^https:\/\/circumuk\.com(?:[/?#].*)?$/.test(text(ctaUrl)) ? text(ctaUrl) : "";
  const safeImageUrl = /^https:\/\/circumuk\.com\/(?:assets\/)+[A-Za-z0-9._/-]+\.(?:png|jpg|jpeg|webp)$/.test(text(imageUrl)) ? text(imageUrl) : "";
  const image = safeImageUrl ? `<p><img src="${escapeHtml(safeImageUrl)}" alt="Welcome to Circum" style="display:block;width:100%;max-width:560px;height:auto;border:0"></p>` : "";
  const htmlParagraphs = paragraphs.map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`).join("");
  const cta = safeUrl ? `<p><a href="${escapeHtml(safeUrl)}" style="display:inline-block;background:#5b21b6;color:#fff;padding:12px 18px;border-radius:6px;text-decoration:none">${escapeHtml(ctaLabel || "Open Circum")}</a></p>` : "";
  const textBody = [heading, ...paragraphs, safeUrl ? `${ctaLabel || "Open Circum"}: ${safeUrl}` : "", footer]
      .filter(Boolean).join("\n\n");
  const html = `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#17151f;line-height:1.6"><span style="display:none;max-height:0;overflow:hidden;opacity:0">${escapeHtml(preheader)}</span>${image}<h1>${escapeHtml(heading)}</h1>${htmlParagraphs}${cta}<p style="color:#635f70">${escapeHtml(footer)}</p></body></html>`;
  return {preheader, heading, text: textBody, html, footer, ctaLabel: safeUrl ? ctaLabel || "Open Circum" : "", ctaUrl: safeUrl};
}

function result({templateId, subject, preheader, heading, paragraphs, ctaLabel, ctaUrl, footer, imageUrl, senderCategory, tags = []}) {
  const rendered = layout({preheader, heading, paragraphs, ctaLabel, ctaUrl, footer, imageUrl});
  const copy = {templateId, subject, senderCategory, providerTags: tags, ...rendered};
  assertCustomerFacingContent(copy);
  return copy;
}

function welcomeHtml({displayName = "", amountText, ctaUrl}) {
  const greeting = safeName(displayName) ? `Hi ${escapeHtml(firstName(displayName))},` : "Hi there,";
  const safeUrl = /^https:\/\/circumuk\.com(?:[/?#].*)?$/.test(text(ctaUrl)) ? text(ctaUrl) : APP_URL;
  const safeAmount = escapeHtml(amountText || "£5.00");
  const cta = `<a href="${escapeHtml(safeUrl)}" style="display:inline-block;padding:17px 37px;border-radius:30px;background:#5b43d6;color:#fff;font-size:17px;font-weight:bold;text-decoration:none">See my 5 Roth</a>`;
  return `<!doctype html><html lang="en"><body style="margin:0;padding:0;background:#edf3ff;color:#182132;font-family:Arial,Helvetica,sans-serif"><span style="display:none;font-size:1px;line-height:1px;color:#f3f6fb;max-height:0;max-width:0;opacity:0;overflow:hidden">Welcome to CIRCUM. Your starter 5 Roth is waiting in the app.</span><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#edf3ff"><tr><td align="center" style="padding:32px 12px"><table role="presentation" class="shell" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background:#fff;border-radius:18px;overflow:hidden"><tr><td align="center" style="padding:44px 48px 18px"><img src="${WELCOME_WORDMARK_URL}" width="186" alt="CIRCUM" style="display:block;width:186px;height:auto;border:0;margin:0 auto"></td></tr><tr><td align="center" style="padding:14px 48px 30px"><h1 style="margin:0;font-family:Georgia,'Times New Roman',serif;font-weight:normal;font-size:43px;line-height:1.14;letter-spacing:-1.2px;color:#111b2d">Welcome to a better<br>way to move things.</h1></td></tr><tr><td style="padding:0 36px 32px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="height:244px;background:#e0eaff;border-radius:18px;overflow:hidden"><tr><td align="center" valign="middle" style="padding:22px 10px"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td width="85" height="82" align="center" style="width:85px;height:82px;background:#1c2277;border-radius:18px 0 0 18px;color:#fff;font-size:34px">●</td><td width="85" height="82" align="center" style="width:85px;height:82px;background:#23c6c8;color:#fff;font-size:44px">→</td><td width="85" height="82" align="center" style="width:85px;height:82px;background:#6d57ee;color:#fff;font-size:37px">◇</td><td width="85" height="82" align="center" style="width:85px;height:82px;background:#ffb84d;border-radius:0 18px 18px 0;color:#fff;font-size:35px">●</td></tr></table><p style="margin:20px 0 0;color:#172a69;font-family:Georgia,'Times New Roman',serif;font-size:29px;letter-spacing:-.5px">Every delivery starts somewhere.</p></td></tr></table></td></tr><tr><td style="padding:8px 48px 0;font-size:18px;line-height:1.7"><p style="margin:0 0 25px">${greeting}</p><p style="margin:0 0 25px">Your account is ready to use, and there’s a welcome gift waiting for you: <strong style="color:#5b43d6">${safeAmount} Roth to get started.</strong> Explore what CIRCUM can do, then use your Roth toward an eligible service when you’re ready.</p><p style="margin:0 0 13px"><strong>Discover what you can do</strong></p><p style="margin:0 0 16px"><strong style="color:#1673e6">Send:</strong> Arrange a parcel delivery from pickup to drop-off, with options shown before you pay.</p><p style="margin:0 0 16px"><strong style="color:#5848df">Gifts:</strong> Send something thoughtful and add a personal story to the moment.</p><p style="margin:0 0 16px"><strong style="color:#102e7a">Business:</strong> Manage deliveries for your work in one place, with business payment tools when you need them.</p><p style="margin:0 0 16px"><strong style="color:#1752d9">Roth:</strong> CIRCUM’s in-app credits can help pay for eligible services. <strong style="white-space:nowrap">£1 = 1 Roth.</strong> Your welcome ${safeAmount} Roth has been added to your wallet, where you can see your balance.</p><p style="margin:0 0 25px"><strong style="color:#15945d">Health+:</strong> Explore delivery options designed for health-related needs. Any eligibility, availability and price are shown in the app.</p></td></tr><tr><td style="padding:2px 48px 23px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#eaf1ff;background-image:linear-gradient(130deg,#eef4ff 0%,#e7edff 40%,#eaf5ff 74%,#f5f3ff 100%);border-radius:24px"><tr><td style="padding:27px 28px;color:#23365e;font-size:18px;line-height:1.55"><span style="color:#4166c9;font-size:13px;font-weight:bold;letter-spacing:1.5px">WELCOME GIFT</span><br><strong style="font-size:27px;color:#2853c7">5 Roth for you</strong><br>That’s <strong>5 Roth</strong> to start with.<br><strong style="display:inline-block;white-space:nowrap;margin:7px 0;color:#2853c7">£1 = 1 Roth</strong><br>Your starter Roth has already been added to your wallet. See your balance in the app.</td></tr></table></td></tr><tr><td style="padding:0 48px;font-size:18px;line-height:1.7"><p style="margin:0 0 13px"><strong>Here’s where to start</strong></p><p style="margin:0 0 25px">Open the app to explore your account. Explore each service at no charge. Your 5 Roth are in your wallet, where you can see your balance. A delivery or optional paid service will show its price before you confirm.</p></td></tr><tr><td align="center" style="padding:5px 48px 31px">${cta}</td></tr><tr><td style="padding:0 48px;font-size:18px;line-height:1.7"><p style="margin:0 0 13px"><strong>A quick word on security</strong></p><p style="margin:0 0 25px">Keep your sign-in details and delivery PINs private. We’ll never ask you to share a password or a one-time sign-in code by email, chat or phone. If anything looks unusual, contact Support.</p><p style="margin:0 0 25px"><strong>Documents</strong><br><a href="${TERMS_URL}" style="color:#1266d4">Terms of Service</a> &nbsp;·&nbsp; <a href="${PRIVACY_URL}" style="color:#1266d4">Privacy Policy</a></p><p style="margin:0 0 31px">Questions? We’re here to help. Here’s to everything you’ll move next.<br><br>Welcome aboard,<br><strong>Team CIRCUM</strong></p></td></tr><tr><td align="center" style="padding:30px 48px 39px;border-top:1px solid #e7edf6;background:#f9fbff;color:#627189;font-size:13px;line-height:1.6"><img src="${WELCOME_WORDMARK_URL}" width="124" alt="CIRCUM" style="display:block;width:124px;height:auto;border:0;margin:0 auto"><br><br>This is a service email about your new CIRCUM account.<br>Need help? Contact Support.</td></tr></table></td></tr></table></body></html>`;
}

function welcome({displayName = "", amount = 5, ctaUrl = APP_URL} = {}) {
  const name = safeName(displayName);
  const amountText = money(amount) || "£5.00";
  const copy = result({
    templateId: "sender-welcome",
    subject: `Welcome to CIRCUM — ${Number(amount) === 5 ? "£5" : amountText} Roth has been added to your wallet`,
    preheader: "Your CIRCUM account is ready. Here’s a little something to help you get started.",
    heading: "Welcome to a better way to move things.",
    paragraphs: [
      name ? `Hi ${firstName(name)},` : "Hi there,",
      "Your account is ready to use, and there’s a welcome gift waiting for you.",
      `To help you get started, we’ve added ${amountText} Roth to your wallet. Roth is CIRCUM credit that can be used toward eligible Circum services and deliveries, subject to our current service rules.`,
      "Whenever you’re ready, you can explore Circum and see what’s available.",
      "Documents: Terms of Service and Privacy Policy.",
      "Questions? We’re here to help. Contact Support.",
    ],
    ctaLabel: "See my 5 Roth",
    ctaUrl,
    footer: "This is a service email about your new CIRCUM account.\n\nThe Circum team",
    senderCategory: "info",
    tags: [{name: "product", value: "account"}, {name: "message", value: "welcome"}],
  });
  copy.html = welcomeHtml({displayName: name, amountText, ctaUrl});
  assertCustomerFacingContent(copy);
  return copy;
}

function bookingConfirmed({reference = "", ctaUrl = APP_URL} = {}) {
  const ref = safeReference(reference);
  return result({
    templateId: "delivery-booking-confirmed",
    subject: "Your CIRCUM delivery booking is confirmed",
    preheader: "Your payment has been confirmed and your delivery is ready to follow.",
    heading: "Your delivery booking is confirmed",
    paragraphs: [
      "Your CIRCUM delivery booking is confirmed and your payment has been received.",
      "You can follow the delivery in Circum as it moves through each stage.",
      ref ? `Booking reference: ${ref}` : "",
    ].filter(Boolean),
    ctaLabel: "View delivery",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "delivery"}, {name: "message", value: "booking-confirmed"}],
  });
}

function deliveryCompleted({reference = "", ctaUrl = APP_URL} = {}) {
  const ref = safeReference(reference);
  return result({
    templateId: "delivery-completed",
    subject: "Your CIRCUM delivery has arrived",
    preheader: "Your delivery has been completed.",
    heading: "Your delivery is complete",
    paragraphs: [
      "Your CIRCUM delivery has been completed. This message confirms the final handover.",
      ref ? `Booking reference: ${ref}` : "",
    ].filter(Boolean),
    ctaLabel: "View delivery",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "delivery"}, {name: "message", value: "completed"}],
  });
}

function cancellationSettled({reference = "", ctaUrl = APP_URL} = {}) {
  const ref = safeReference(reference);
  return result({
    templateId: "delivery-cancellation-settled",
    subject: "Your CIRCUM delivery cancellation is complete",
    preheader: "Your cancellation and any applicable payment settlement have been completed.",
    heading: "Your delivery cancellation is complete",
    paragraphs: [
      "The cancellation for your CIRCUM delivery has been completed.",
      "Any applicable refund or fee settlement has been recorded against the booking.",
      ref ? `Booking reference: ${ref}` : "",
    ].filter(Boolean),
    ctaLabel: "View payment details",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "delivery"}, {name: "message", value: "cancellation"}],
  });
}

function businessInvoicePaid({reference = "", ctaUrl = APP_URL} = {}) {
  const ref = safeReference(reference);
  return result({
    templateId: "business-invoice-paid",
    subject: "Your CIRCUM Business invoice is paid",
    preheader: "Your CIRCUM Business payment has been received and your invoice is settled.",
    heading: "Your CIRCUM Business invoice is paid",
    paragraphs: [
      "We have received payment for your CIRCUM Business invoice.",
      "Your account is up to date. Sign in to review the invoice and payment record.",
      ref ? `Invoice reference: ${ref}` : "",
    ].filter(Boolean),
    ctaLabel: "View invoice",
    ctaUrl,
    senderCategory: "business",
    tags: [{name: "product", value: "business"}, {name: "message", value: "invoice-paid"}],
  });
}

function rothActivity({displayName = "", movement = "updated", amount = null, reference = "", ctaUrl = APP_URL} = {}) {
  const amountText = money(amount);
  const descriptions = {
    credited: amountText ? `${amountText} Roth has been added to your wallet.` : "Roth has been added to your wallet.",
    debited: amountText ? `${amountText} Roth has been used from your wallet.` : "Roth has been used from your wallet.",
    refunded: amountText ? `${amountText} Roth has been returned to your wallet.` : "Roth has been returned to your wallet.",
    restored: amountText ? `${amountText} Roth has been restored to your wallet.` : "Roth has been restored to your wallet.",
    updated: "Your Roth wallet has been updated.",
  };
  const description = descriptions[movement] || descriptions.updated;
  return result({
    templateId: "roth-activity",
    subject: "Your CIRCUM Roth wallet has been updated",
    preheader: description,
    heading: displayName ? `Your Roth wallet, ${firstName(displayName)}` : "Your Roth wallet has been updated",
    paragraphs: [description, "Roth can be used toward eligible Circum services and deliveries under the current product rules.", reference ? `Reference: ${safeReference(reference)}` : ""].filter(Boolean),
    ctaLabel: "View Roth wallet",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "roth"}, {name: "message", value: "wallet-update"}],
  });
}

function referralReward({ctaUrl = APP_URL} = {}) {
  return result({
    templateId: "referral-reward",
    subject: "Your CIRCUM referral reward is ready",
    preheader: "Your referral reward has been added to your Roth wallet.",
    heading: "Your referral reward is ready",
    paragraphs: ["Your referral reward has been added to your Roth wallet.", "You can use Roth toward eligible Circum services and deliveries under the current product rules."],
    ctaLabel: "View your wallet",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "referrals"}, {name: "message", value: "reward"}],
  });
}

function riderDecision({decision, ctaUrl = APP_URL} = {}) {
  const copy = {
    approved: {
      subject: "Your CIRCUM Rider application has been approved",
      preheader: "Your Rider application has been approved. Review the next steps in the Rider app.",
      heading: "Your Rider application is approved",
      body: "Your Rider application has been approved. Open the Rider app to review the next steps before you begin.",
    },
    rejected: {
      subject: "An update about your CIRCUM Rider application",
      preheader: "There is an update about your Rider application.",
      heading: "An update about your Rider application",
      body: "There is an update about your Rider application. Open the Rider app to review the information available to you.",
    },
    more_information_requested: {
      subject: "A little more information is needed for your CIRCUM Rider application",
      preheader: "Please open the Rider app to see what is needed next.",
      heading: "A little more information is needed",
      body: "Please open the Rider app to see the next step for your application. We only ask for information needed to review your application.",
    },
  }[text(decision).toLowerCase()] || null;
  if (!copy) throw new Error("Unsupported Rider application decision.");
  return result({
    templateId: `rider-application-${text(decision).toLowerCase()}`,
    subject: copy.subject,
    preheader: copy.preheader,
    heading: copy.heading,
    paragraphs: [copy.body],
    ctaLabel: "Open Rider",
    ctaUrl,
    senderCategory: "info",
    tags: [{name: "product", value: "rider"}, {name: "message", value: "application-update"}],
  });
}

const HEALTH_COPY = Object.freeze({
  scheduled: ["Your Health+ collection is scheduled", "Your Health+ collection has been scheduled. We will keep you updated as it progresses."],
  assigned: ["A rider has been assigned to your Health+ collection", "A verified rider has been assigned to your Health+ collection."],
  en_route_pickup: ["Your Health+ rider is on the way", "Your rider is travelling to the collection point."],
  awaiting_pharmacy_collection: ["Your Health+ rider is ready at the collection point", "Your rider is ready to collect from the pharmacy."],
  collected: ["Your Health+ prescription has been collected", "Your prescription has been collected securely and is now moving through the next step."],
  out_for_delivery: ["Your Health+ delivery is on the way", "Your Health+ delivery is on its way to you."],
  delivered: ["Your Health+ delivery is complete", "Your Health+ delivery has been completed."],
  prescription_not_ready: ["Your Health+ collection needs an update", "The prescription was not ready when our rider arrived. Circum is coordinating the next step."],
  customer_unavailable: ["We need to rearrange your Health+ delivery", "We could not complete the delivery. Circum will help arrange the next step."],
  escalated: ["Your Health+ delivery needs our attention", "Your Health+ delivery has been referred to our team for review. We will update you when the next step is confirmed."],
  rescheduled: ["Your Health+ collection has been rescheduled", "Your Health+ collection has been rescheduled. We will keep you updated with the arranged time."],
  override_completed: ["Your Health+ delivery is complete", "Your Health+ delivery has been completed following a review."],
  reminder_24h: ["Your Health+ collection is tomorrow", "Your Health+ collection is scheduled for tomorrow. Please keep the arranged time available."],
  reminder_2h: ["Your Health+ collection is due soon", "Your Health+ collection is scheduled in approximately two hours."],
});

function healthUpdate({type, ctaUrl = APP_URL} = {}) {
  const copy = HEALTH_COPY[text(type).toLowerCase()];
  if (!copy) throw new Error("Unsupported Health+ notification.");
  return result({
    templateId: `health-update-${text(type).toLowerCase()}`,
    subject: copy[0],
    preheader: copy[1],
    heading: copy[0],
    paragraphs: [copy[1]],
    ctaLabel: "View Health+",
    ctaUrl,
    senderCategory: "health",
    tags: [{name: "product", value: "health-plus"}, {name: "message", value: "status-update"}],
  });
}

function giftPaymentConfirmed(options = {}) {
  const copy = gifts.paymentConfirmed(options);
  assertCustomerFacingContent(copy);
  return copy;
}

function giftDelivered(options = {}) {
  const copy = gifts.delivered(options);
  assertCustomerFacingContent(copy);
  return copy;
}

function giftStory({role, storyUrl} = {}) {
  const copy = gifts.story({role, storyUrl});
  assertCustomerFacingContent(copy);
  return copy;
}

function assertCustomerFacingContent(copy) {
  const fields = visibleCustomerText(copy).toLowerCase();
  if (/[a-z][a-z0-9]*_[a-z0-9_]+/.test(fields)) throw new Error("customer_copy_contains_snake_case");
  for (const token of FORBIDDEN_CUSTOMER_TOKENS) {
    if (fields.includes(token)) throw new Error(`customer_copy_contains_internal_token:${token}`);
  }
  return true;
}

function visibleCustomerText(copy) {
  return [copy.subject, copy.preheader, copy.heading, copy.text, copy.html, copy.ctaLabel, copy.footer]
      .filter(Boolean).join(" ")
      .replace(/https?:\/\/[^\s"'<>]+/gi, " ")
      .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, " ");
}

module.exports = {
  APP_URL,
  FORBIDDEN_CUSTOMER_TOKENS,
  assertCustomerFacingContent,
  visibleCustomerText,
  bookingConfirmed,
  businessInvoicePaid,
  cancellationSettled,
  deliveryCompleted,
  giftDelivered,
  giftPaymentConfirmed,
  giftStory,
  healthUpdate,
  referralReward,
  riderDecision,
  rothActivity,
  welcome,
};
